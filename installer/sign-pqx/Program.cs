using System.IO;
using System.IO.Packaging;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Cryptography.Xml;
using System.Xml;
using Azure.Identity;
using Azure.Security.KeyVault.Certificates;
using Azure.Security.KeyVault.Keys.Cryptography;
using KvSignatureAlgorithm = Azure.Security.KeyVault.Keys.Cryptography.SignatureAlgorithm;

if (args.Length < 3)
{
    Console.Error.WriteLine("Usage: sign-pqx <vault-url> <cert-name> <pqx-path>");
    return 1;
}

string vaultUrl = args[0];
string certName = args[1];
string pqxPath = args[2];

if (!File.Exists(pqxPath))
{
    Console.Error.WriteLine($"File not found: {pqxPath}");
    return 1;
}

long sizeBefore = new FileInfo(pqxPath).Length;
Console.WriteLine($"Package:     {pqxPath} ({sizeBefore} bytes)");
Console.WriteLine($"Vault:       {vaultUrl}");
Console.WriteLine($"Certificate: {certName}");

// Authenticate via DefaultAzureCredential (OIDC in GitHub Actions, CLI locally)
var credential = new DefaultAzureCredential();

// Get public certificate from Key Vault (only needs certificates/get permission)
Console.Write("Fetching certificate... ");
var certClient = new CertificateClient(new Uri(vaultUrl), credential);
KeyVaultCertificateWithPolicy kvCert = certClient.GetCertificate(certName);
var publicCert = new X509Certificate2(kvCert.Cer);
Console.WriteLine($"{publicCert.Subject}");
Console.WriteLine($"Thumbprint:  {publicCert.Thumbprint}");

using RSA? certPubKey = publicCert.GetRSAPublicKey();
if (certPubKey is null)
{
    Console.Error.WriteLine("Certificate does not contain an RSA public key.");
    return 1;
}

// Create Key Vault-backed RSA (private key never leaves Key Vault)
var cryptoClient = new CryptographyClient(kvCert.KeyId, credential);
RSAParameters pubParams = certPubKey.ExportParameters(includePrivateParameters: false);
using var rsaKeyVault = new KeyVaultRsa(cryptoClient, pubParams);

// Phase 1: Sign with a temporary cert to create the OPC signature structure.
// PackageDigitalSignatureManager.Sign() requires CopyWithPrivateKey which calls
// ExportParameters(true) — impossible for Key Vault keys. So we sign with a temp
// key first, then replace the SignatureValue and certificate in Phase 2.
Console.Write("Creating OPC signature structure... ");
using var tempRsa = RSA.Create(certPubKey.KeySize);
var req = new CertificateRequest("CN=Temp", tempRsa, HashAlgorithmName.SHA256,
    RSASignaturePadding.Pkcs1);
using var tempCert = req.CreateSelfSigned(DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddHours(1));

using (Package package = Package.Open(pqxPath, FileMode.Open, FileAccess.ReadWrite))
{
    var dsm = new PackageDigitalSignatureManager(package)
    {
        CertificateOption = CertificateEmbeddingOption.InSignaturePart
    };

    var partsToSign = new List<Uri>();
    foreach (PackagePart part in package.GetParts())
        partsToSign.Add(part.Uri);

    partsToSign.Add(dsm.SignatureOrigin);
    partsToSign.Add(PackUriHelper.GetRelationshipPartUri(dsm.SignatureOrigin));
    partsToSign.Add(PackUriHelper.GetRelationshipPartUri(new Uri("/", UriKind.RelativeOrAbsolute)));

    dsm.Sign(partsToSign, tempCert);
}
Console.WriteLine("OK");

// Phase 2: Re-sign SignedInfo with Key Vault and replace the embedded certificate.
// The reference digests (hashes of actual part content) remain valid since the
// package content hasn't changed — only the SignatureValue and KeyInfo change.
Console.Write("Re-signing with Key Vault... ");
const string dsigNs = "http://www.w3.org/2000/09/xmldsig#";

using (Package package = Package.Open(pqxPath, FileMode.Open, FileAccess.ReadWrite))
{
    var dsm = new PackageDigitalSignatureManager(package);

    foreach (PackageDigitalSignature sig in dsm.Signatures)
    {
        PackagePart sigPart = sig.SignaturePart;

        // Read signature XML
        var doc = new XmlDocument();
        doc.PreserveWhitespace = true;
        using (Stream stream = sigPart.GetStream(FileMode.Open, FileAccess.Read))
            doc.Load(stream);

        var nsMgr = new XmlNamespaceManager(doc.NameTable);
        nsMgr.AddNamespace("ds", dsigNs);

        // Get SignedInfo and verify it uses RSA-SHA256
        var signedInfoEl = (XmlElement)doc.SelectSingleNode("//ds:Signature/ds:SignedInfo", nsMgr)!;
        string? sigMethod = signedInfoEl.SelectSingleNode("ds:SignatureMethod/@Algorithm", nsMgr)?.Value;
        if (sigMethod != "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256")
            throw new CryptographicException($"Expected RSA-SHA256 SignatureMethod, got: {sigMethod}");

        // Canonicalize SignedInfo using inclusive C14N (matching CanonicalizationMethod)
        var c14n = new XmlDsigC14NTransform();
        var siDoc = new XmlDocument { PreserveWhitespace = true };
        siDoc.LoadXml(signedInfoEl.OuterXml);
        c14n.LoadInput(siDoc);
        byte[] canonicalBytes;
        using (var output = (Stream)c14n.GetOutput(typeof(Stream)))
        using (var ms = new MemoryStream())
        {
            output.CopyTo(ms);
            canonicalBytes = ms.ToArray();
        }

        // Hash the canonical SignedInfo and sign with Key Vault
        byte[] hash = SHA256.HashData(canonicalBytes);
        byte[] kvSignature = rsaKeyVault.SignHash(hash, HashAlgorithmName.SHA256,
            RSASignaturePadding.Pkcs1);

        // Replace SignatureValue
        var sigValueNode = doc.SelectSingleNode("//ds:Signature/ds:SignatureValue", nsMgr)!;
        sigValueNode.InnerText = Convert.ToBase64String(kvSignature);

        // Rebuild KeyInfo entirely — the temp cert left behind KeyName and RSAKeyValue
        // elements with the wrong key. KeyInfo is NOT covered by the signature, so we
        // can safely replace it. Only include X509Data with the real Key Vault cert.
        var keyInfoNode = doc.SelectSingleNode("//ds:Signature/ds:KeyInfo", nsMgr)!;
        keyInfoNode.RemoveAll();
        var x509Data = doc.CreateElement("X509Data", dsigNs);
        var x509Cert = doc.CreateElement("X509Certificate", dsigNs);
        x509Cert.InnerText = Convert.ToBase64String(publicCert.RawData);
        x509Data.AppendChild(x509Cert);
        keyInfoNode.AppendChild(x509Data);

        // Write modified XML back to the signature part
        using (Stream stream = sigPart.GetStream(FileMode.Create, FileAccess.Write))
        {
            var settings = new XmlWriterSettings { CloseOutput = false };
            using var writer = XmlWriter.Create(stream, settings);
            doc.Save(writer);
        }
    }
}
Console.WriteLine("OK");

// Verify
Console.Write("Verifying... ");
using (Package package = Package.Open(pqxPath, FileMode.Open, FileAccess.Read))
{
    var dsm = new PackageDigitalSignatureManager(package);
    if (!dsm.IsSigned)
    {
        Console.Error.WriteLine("FAILED — package is not signed");
        return 1;
    }

    var result = dsm.VerifySignatures(true);
    Console.WriteLine(result == System.IO.Packaging.VerifyResult.Success ? "OK" : $"FAILED ({result})");
    if (result != System.IO.Packaging.VerifyResult.Success)
        return 1;
}

long sizeAfter = new FileInfo(pqxPath).Length;
Console.WriteLine($"Done: {sizeBefore} -> {sizeAfter} bytes");
return 0;

// ═══════════════════════════════════════════════════════════════
// RSA implementation that delegates signing to Azure Key Vault
// ═══════════════════════════════════════════════════════════════

sealed class KeyVaultRsa : RSA
{
    private readonly CryptographyClient _client;
    private readonly RSA _publicKey;

    public KeyVaultRsa(CryptographyClient client, RSAParameters publicParameters)
    {
        _client = client;
        _publicKey = RSA.Create();
        _publicKey.ImportParameters(publicParameters);
        KeySizeValue = _publicKey.KeySize;
        LegalKeySizesValue = _publicKey.LegalKeySizes;
    }

    public override RSAParameters ExportParameters(bool includePrivateParameters)
    {
        if (includePrivateParameters)
            throw new CryptographicException("Private key is in Azure Key Vault.");
        return _publicKey.ExportParameters(false);
    }

    public override void ImportParameters(RSAParameters parameters)
        => throw new NotSupportedException();

    public override byte[] SignHash(byte[] hash, HashAlgorithmName hashAlgorithm,
        RSASignaturePadding padding)
    {
        if (padding != RSASignaturePadding.Pkcs1)
            throw new CryptographicException($"Unsupported padding: {padding}");

        var algorithm = hashAlgorithm.Name switch
        {
            "SHA256" => KvSignatureAlgorithm.RS256,
            "SHA384" => KvSignatureAlgorithm.RS384,
            "SHA512" => KvSignatureAlgorithm.RS512,
            _ => throw new CryptographicException($"Unsupported hash algorithm: {hashAlgorithm.Name}")
        };
        return _client.Sign(algorithm, hash).Signature;
    }

    public override bool VerifyHash(byte[] hash, byte[] signature,
        HashAlgorithmName hashAlgorithm, RSASignaturePadding padding)
        => _publicKey.VerifyHash(hash, signature, hashAlgorithm, padding);

    public override byte[] Encrypt(byte[] data, RSAEncryptionPadding padding)
        => _publicKey.Encrypt(data, padding);

    public override byte[] Decrypt(byte[] data, RSAEncryptionPadding padding)
        => throw new NotSupportedException();

    protected override void Dispose(bool disposing)
    {
        if (disposing) _publicKey.Dispose();
        base.Dispose(disposing);
    }
}
