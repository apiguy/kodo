# frozen_string_literal: true

RSpec.describe Kodo::Memory::Encryption do
  let(:passphrase) { "test-passphrase-12345" }
  let(:plaintext) { "Hello, this is secret data!" }

  describe ".encrypt / .decrypt" do
    it "round-trips plaintext through encrypt and decrypt" do
      encrypted = described_class.encrypt(plaintext, key: passphrase)
      decrypted = described_class.decrypt(encrypted, key: passphrase)

      expect(decrypted).to eq(plaintext)
    end

    it "produces different ciphertext each time (random salt/IV)" do
      enc1 = described_class.encrypt(plaintext, key: passphrase)
      enc2 = described_class.encrypt(plaintext, key: passphrase)

      expect(enc1).not_to eq(enc2)
    end

    it "handles empty plaintext" do
      encrypted = described_class.encrypt("", key: passphrase)
      decrypted = described_class.decrypt(encrypted, key: passphrase)

      expect(decrypted).to eq("")
    end

    it "handles unicode content" do
      unicode = "鼓動 heartbeat 🥁"
      encrypted = described_class.encrypt(unicode, key: passphrase)
      decrypted = described_class.decrypt(encrypted, key: passphrase)

      expect(decrypted).to eq(unicode)
    end

    it "handles large content" do
      large = "x" * 100_000
      encrypted = described_class.encrypt(large, key: passphrase)
      decrypted = described_class.decrypt(encrypted, key: passphrase)

      expect(decrypted).to eq(large)
    end
  end

  describe "wrong key rejection" do
    it "raises on decrypt with wrong passphrase" do
      encrypted = described_class.encrypt(plaintext, key: passphrase)

      expect {
        described_class.decrypt(encrypted, key: "wrong-passphrase")
      }.to raise_error(Kodo::Error, /Decryption failed/)
    end

    it "raises on decrypt of tampered data" do
      encrypted = described_class.encrypt(plaintext, key: passphrase)
      # Flip a byte in the ciphertext portion
      tampered = encrypted.dup
      tampered.setbyte(tampered.bytesize - 1, tampered.getbyte(tampered.bytesize - 1) ^ 0xFF)

      expect {
        described_class.decrypt(tampered, key: passphrase)
      }.to raise_error(Kodo::Error, /Decryption failed/)
    end
  end

  describe ".encrypted?" do
    it "returns true for encrypted data" do
      encrypted = described_class.encrypt(plaintext, key: passphrase)
      expect(described_class.encrypted?(encrypted)).to be true
    end

    it "returns false for plaintext" do
      expect(described_class.encrypted?(plaintext)).to be false
    end

    it "returns false for nil" do
      expect(described_class.encrypted?(nil)).to be false
    end

    it "returns false for empty string" do
      expect(described_class.encrypted?("")).to be false
    end

    it "returns false for short data" do
      expect(described_class.encrypted?("KODO")).to be false
    end

    it "detects the KODO magic header" do
      encrypted = described_class.encrypt("test", key: passphrase)
      expect(encrypted.byteslice(0, 4)).to eq("KODO")
    end
  end

  describe ".derive_key" do
    it "produces 32-byte key" do
      salt = OpenSSL::Random.random_bytes(32)
      key = described_class.derive_key(passphrase, salt: salt)

      expect(key.bytesize).to eq(32)
    end

    it "produces same key for same passphrase and salt" do
      salt = OpenSSL::Random.random_bytes(32)
      key1 = described_class.derive_key(passphrase, salt: salt)
      key2 = described_class.derive_key(passphrase, salt: salt)

      expect(key1).to eq(key2)
    end

    it "produces different keys for different salts" do
      salt1 = OpenSSL::Random.random_bytes(32)
      salt2 = OpenSSL::Random.random_bytes(32)
      key1 = described_class.derive_key(passphrase, salt: salt1)
      key2 = described_class.derive_key(passphrase, salt: salt2)

      expect(key1).not_to eq(key2)
    end
  end

  describe "format validation" do
    it "raises for data without KODO header" do
      expect {
        described_class.decrypt("not encrypted data that is long enough to pass size check!!", key: passphrase)
      }.to raise_error(Kodo::Error, /missing KODO header/)
    end
  end
end
