using System.Numerics;
using System.Security.Cryptography;
using System.Text;

namespace SpiderBuddy.Core;

/// <summary>
/// Ed25519 (RFC 8032) signing and verification. The macOS app uses Sparkle's EdDSA
/// signatures; the Windows feed uses the same curve and a separate Windows key. Kept in
/// the portable core because it is pure arithmetic, with no OS or network calls.
///
/// Verification is used by the app on downloaded installers. Signing is used by the
/// release tool only; a seed must never be shipped with the app.
/// </summary>
public static class Ed25519
{
    public const int SeedBytes = 32;
    public const int PublicKeyBytes = 32;
    public const int SignatureBytes = 64;

    static readonly BigInteger P = BigInteger.Pow(2, 255) - 19;
    static readonly BigInteger L = BigInteger.Pow(2, 252) + BigInteger.Parse("27742317777372353535851937790883648493");
    static readonly BigInteger D = Mod(-121665 * Inverse(121666));
    static readonly BigInteger I = BigInteger.ModPow(2, (P - 1) / 4, P);
    static readonly BigInteger BaseX = BigInteger.Parse("15112221349535400772501151409588531511454012693041857206046113283949847762202");
    static readonly BigInteger BaseY = BigInteger.Parse("46316835694926478169428394003475163141307993866256225615783033603165251855960");
    static readonly Point Base = new(BaseX, BaseY, BigInteger.One, Mod(BaseX * BaseY));
    static readonly Point Identity = new(BigInteger.Zero, BigInteger.One, BigInteger.One, BigInteger.Zero);

    public static byte[] NewSeed() => RandomNumberGenerator.GetBytes(SeedBytes);

    public static byte[] PublicKey(ReadOnlySpan<byte> seed)
    {
        if (seed.Length != SeedBytes) throw new ArgumentException("An Ed25519 seed is 32 bytes.", nameof(seed));
        var (scalar, _) = Expand(seed);
        return Encode(ScalarMultiply(Base, scalar));
    }

    /// <summary>Sign a message with a 32-byte seed. Returns the 64-byte signature.</summary>
    public static byte[] Sign(ReadOnlySpan<byte> seed, ReadOnlySpan<byte> message)
    {
        if (seed.Length != SeedBytes) throw new ArgumentException("An Ed25519 seed is 32 bytes.", nameof(seed));
        var (a, prefix) = Expand(seed);
        byte[] publicKey = Encode(ScalarMultiply(Base, a));

        byte[] rInput = new byte[prefix.Length + message.Length];
        prefix.CopyTo(rInput, 0);
        message.CopyTo(rInput.AsSpan(prefix.Length));
        BigInteger r = FromLittleEndian(SHA512(rInput)) % L;

        byte[] rEncoded = Encode(ScalarMultiply(Base, r));
        byte[] kInput = new byte[rEncoded.Length + publicKey.Length + message.Length];
        rEncoded.CopyTo(kInput, 0);
        publicKey.AsSpan().CopyTo(kInput.AsSpan(rEncoded.Length));
        message.CopyTo(kInput.AsSpan(rEncoded.Length + publicKey.Length));
        BigInteger k = FromLittleEndian(SHA512(kInput)) % L;

        BigInteger s = (r + k * a) % L;
        var signature = new byte[SignatureBytes];
        rEncoded.CopyTo(signature, 0);
        ToLittleEndian(s, signature.AsSpan(32, 32));
        return signature;
    }

    public static bool Verify(ReadOnlySpan<byte> publicKey, ReadOnlySpan<byte> message, ReadOnlySpan<byte> signature)
    {
        if (publicKey.Length != PublicKeyBytes || signature.Length != SignatureBytes) return false;
        if (!TryDecode(publicKey, out Point a) || IsSmallOrder(a)) return false;
        if (!TryDecode(signature[..32], out Point r)) return false;
        if (!SameEncoding(signature[..32], Encode(r))) return false;
        BigInteger s = FromLittleEndian(signature[32..]);
        if (s >= L) return false;

        byte[] kInput = new byte[32 + 32 + message.Length];
        signature[..32].CopyTo(kInput);
        publicKey.CopyTo(kInput.AsSpan(32));
        message.CopyTo(kInput.AsSpan(64));
        BigInteger k = FromLittleEndian(SHA512(kInput)) % L;

        Point left = ScalarMultiply(Base, s);
        Point right = Add(r, ScalarMultiply(a, k));
        return SamePoint(left, right);
    }

    /// <summary>Verify a file without holding it in memory. The file is read twice.</summary>
    public static bool VerifyFile(string path, ReadOnlySpan<byte> publicKey, ReadOnlySpan<byte> signature)
    {
        if (publicKey.Length != PublicKeyBytes || signature.Length != SignatureBytes) return false;
        if (!TryDecode(publicKey, out Point a) || IsSmallOrder(a)) return false;
        if (!TryDecode(signature[..32], out Point r)) return false;
        if (!SameEncoding(signature[..32], Encode(r))) return false;
        BigInteger s = FromLittleEndian(signature[32..]);
        if (s >= L) return false;

        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA512);
        hash.AppendData(signature[..32]);
        hash.AppendData(publicKey);
        using (var stream = File.OpenRead(path))
        {
            var buffer = new byte[128 * 1024];
            int read;
            while ((read = stream.Read(buffer, 0, buffer.Length)) > 0) hash.AppendData(buffer, 0, read);
        }
        BigInteger k = FromLittleEndian(hash.GetHashAndReset()) % L;
        return SamePoint(ScalarMultiply(Base, s), Add(r, ScalarMultiply(a, k)));
    }

    /// <summary>Sign a file without holding it in memory. The file is read twice.</summary>
    public static byte[] SignFile(ReadOnlySpan<byte> seed, string path)
    {
        if (seed.Length != SeedBytes) throw new ArgumentException("An Ed25519 seed is 32 bytes.", nameof(seed));
        var (a, prefix) = Expand(seed);
        byte[] publicKey = Encode(ScalarMultiply(Base, a));

        BigInteger r;
        using (var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA512))
        {
            hash.AppendData(prefix);
            AppendFile(hash, path);
            r = FromLittleEndian(hash.GetHashAndReset()) % L;
        }

        byte[] rEncoded = Encode(ScalarMultiply(Base, r));
        BigInteger k;
        using (var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA512))
        {
            hash.AppendData(rEncoded);
            hash.AppendData(publicKey);
            AppendFile(hash, path);
            k = FromLittleEndian(hash.GetHashAndReset()) % L;
        }

        BigInteger s = (r + k * a) % L;
        var signature = new byte[SignatureBytes];
        rEncoded.CopyTo(signature, 0);
        ToLittleEndian(s, signature.AsSpan(32, 32));
        return signature;
    }

    static void AppendFile(IncrementalHash hash, string path)
    {
        using var stream = File.OpenRead(path);
        var buffer = new byte[128 * 1024];
        int read;
        while ((read = stream.Read(buffer, 0, buffer.Length)) > 0) hash.AppendData(buffer, 0, read);
    }

    static (BigInteger scalar, byte[] prefix) Expand(ReadOnlySpan<byte> seed)
    {
        byte[] h = SHA512(seed);
        var aBytes = h.AsSpan(0, 32).ToArray();
        aBytes[0] &= 248;
        aBytes[31] &= 127;
        aBytes[31] |= 64;
        return (FromLittleEndian(aBytes), h.AsSpan(32, 32).ToArray());
    }

    static byte[] SHA512(ReadOnlySpan<byte> data) => System.Security.Cryptography.SHA512.HashData(data);

    static bool IsSmallOrder(Point p) => SamePoint(ScalarMultiply(p, 8), Identity);

    static Point ScalarMultiply(Point p, BigInteger scalar)
    {
        Point result = Identity;
        Point addend = p;
        while (scalar > 0)
        {
            if (!(scalar & BigInteger.One).IsZero) result = Add(result, addend);
            addend = Double(addend);
            scalar >>= 1;
        }
        return result;
    }

    static Point Add(Point p, Point q)
    {
        BigInteger a = Mod((p.Y - p.X) * (q.Y - q.X));
        BigInteger b = Mod((p.Y + p.X) * (q.Y + q.X));
        BigInteger c = Mod(p.T * 2 * D * q.T);
        BigInteger d = Mod(p.Z * 2 * q.Z);
        BigInteger e = Mod(b - a);
        BigInteger f = Mod(d - c);
        BigInteger g = Mod(d + c);
        BigInteger h = Mod(b + a);
        return new Point(Mod(e * f), Mod(g * h), Mod(f * g), Mod(e * h));
    }

    static Point Double(Point p)
    {
        BigInteger a = Mod(p.X * p.X);
        BigInteger b = Mod(p.Y * p.Y);
        BigInteger c = Mod(2 * p.Z * p.Z);
        BigInteger d = Mod(-a);
        BigInteger e = Mod((p.X + p.Y) * (p.X + p.Y) - a - b);
        BigInteger g = Mod(d + b);
        BigInteger f = Mod(g - c);
        BigInteger h = Mod(d - b);
        return new Point(Mod(e * f), Mod(g * h), Mod(f * g), Mod(e * h));
    }

    static bool TryDecode(ReadOnlySpan<byte> encoded, out Point point)
    {
        point = default;
        if (encoded.Length != 32) return false;
        var yBytes = encoded.ToArray();
        int sign = yBytes[31] >> 7;
        yBytes[31] &= 0x7f;
        BigInteger y = FromLittleEndian(yBytes);
        if (y >= P) return false;

        BigInteger y2 = Mod(y * y);
        BigInteger u = Mod(y2 - 1);
        BigInteger v = Mod(D * y2 + 1);
        if (v.IsZero) return false;

        BigInteger x = BigInteger.ModPow(Mod(u * Inverse(v)), (P + 3) / 8, P);
        if (Mod(x * x * v - u) != 0) x = Mod(x * I);
        if (Mod(x * x * v - u) != 0) return false;

        if (x.IsZero && sign == 1) return false;
        bool odd = !x.IsEven;
        if (odd != (sign == 1)) x = Mod(-x);
        point = new Point(x, y, BigInteger.One, Mod(x * y));
        return true;
    }

    static byte[] Encode(Point p)
    {
        BigInteger zInv = Inverse(p.Z);
        BigInteger x = Mod(p.X * zInv);
        BigInteger y = Mod(p.Y * zInv);
        var output = new byte[32];
        ToLittleEndian(y, output);
        if (!x.IsEven) output[31] |= 0x80;
        return output;
    }

    static bool SamePoint(Point a, Point b) => Encode(a).AsSpan().SequenceEqual(Encode(b));

    static bool SameEncoding(ReadOnlySpan<byte> a, ReadOnlySpan<byte> b) => a.SequenceEqual(b);

    static BigInteger Mod(BigInteger v)
    {
        BigInteger r = v % P;
        return r.Sign < 0 ? r + P : r;
    }

    static BigInteger Inverse(BigInteger v) => BigInteger.ModPow(Mod(v), P - 2, P);

    static BigInteger FromLittleEndian(ReadOnlySpan<byte> bytes)
    {
        var be = new byte[bytes.Length + 1];
        for (int i = 0; i < bytes.Length; i++) be[bytes.Length - i] = bytes[i];
        return new BigInteger(be, isUnsigned: true, isBigEndian: true);
    }

    static void ToLittleEndian(BigInteger value, Span<byte> output)
    {
        output.Clear();
        var bytes = value.ToByteArray(isUnsigned: true, isBigEndian: true);
        for (int i = 0; i < bytes.Length && i < output.Length; i++)
            output[i] = bytes[bytes.Length - 1 - i];
    }

    readonly record struct Point(BigInteger X, BigInteger Y, BigInteger Z, BigInteger T);
}

/// <summary>A tiny JSON file used for the release-only Windows update key.</summary>
public sealed record UpdateSigningKey(string Seed, string PublicKey)
{
    public static UpdateSigningKey Create()
    {
        byte[] seed = Ed25519.NewSeed();
        return new UpdateSigningKey(Convert.ToBase64String(seed), Convert.ToBase64String(Ed25519.PublicKey(seed)));
    }

    public static UpdateSigningKey? FromJson(string? json)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(json)) return null;
            var key = System.Text.Json.JsonSerializer.Deserialize<UpdateSigningKey>(json);
            if (key is null) return null;
            byte[] seed = Convert.FromBase64String(key.Seed);
            if (seed.Length != Ed25519.SeedBytes) return null;
            return new UpdateSigningKey(Convert.ToBase64String(seed), Convert.ToBase64String(Ed25519.PublicKey(seed)));
        }
        catch { return null; }
    }

    public string ToJson() => System.Text.Json.JsonSerializer.Serialize(this, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
}
