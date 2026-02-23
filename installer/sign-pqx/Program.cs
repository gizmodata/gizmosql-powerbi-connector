using System.IO.Packaging;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Azure.Identity;
using Azure.Security.KeyVault.Certificates;
using Azure.Security.KeyVault.Keys.Cryptography;

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

if (publicCert.GetRSAPublicKey() is null)
{
    Console.Error.WriteLine("Certificate does not contain an RSA public key.");
    return 1;
}

// Create Key Vault-backed RSA (private key never leaves Key Vault)
var cryptoClient = new CryptographyClient(kvCert.KeyId, credential);
using RSA certPubKey = publicCert.GetRSAPublicKey()!;
RSAParameters pubParams = certPubKey.ExportParameters(includePrivateParameters: false);
using var rsaKeyVault = new KeyVaultRsa(cryptoClient, pubParams);

// Bind the Key Vault RSA to the certificate
using X509Certificate2 signingCert = publicCert.CopyWithPrivateKey(rsaKeyVault);
Console.WriteLine($"HasPrivateKey: {signingCert.HasPrivateKey}");

// Sign the OPC package
Console.Write("Signing... ");
using (Package package = Package.Open(pqxPath, FileMode.Open, FileAccess.ReadWrite))
{
    var dsm = new PackageDigitalSignatureManager(package)
    {
        CertificateOption = CertificateEmbeddingOption.InSignaturePart
    };

    // Sign all parts
    var partsToSign = new List<Uri>();
    foreach (PackagePart part in package.GetParts())
        partsToSign.Add(part.Uri);

    // Include OPC signature infrastructure
    partsToSign.Add(dsm.SignatureOrigin);
    partsToSign.Add(PackUriHelper.GetRelationshipPartUri(dsm.SignatureOrigin));
    partsToSign.Add(PackUriHelper.GetRelationshipPartUri(new Uri("/", UriKind.RelativeOrAbsolute)));

    dsm.Sign(partsToSign, signingCert);
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
            "SHA256" => SignatureAlgorithm.RS256,
            "SHA384" => SignatureAlgorithm.RS384,
            "SHA512" => SignatureAlgorithm.RS512,
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
