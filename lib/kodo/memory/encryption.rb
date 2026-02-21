# frozen_string_literal: true

require "openssl"

module Kodo
  module Memory
    module Encryption
      MAGIC = "KODO"
      FORMAT_VERSION = 1
      SALT_LENGTH = 32
      IV_LENGTH = 12
      TAG_LENGTH = 16
      KEY_LENGTH = 32
      PBKDF2_ITERATIONS = 600_000
      HEADER_LENGTH = MAGIC.bytesize + 1 + SALT_LENGTH + IV_LENGTH + TAG_LENGTH # 65 bytes

      class << self
        def derive_key(passphrase, salt:)
          OpenSSL::KDF.pbkdf2_hmac(
            passphrase,
            salt: salt,
            iterations: PBKDF2_ITERATIONS,
            length: KEY_LENGTH,
            hash: "SHA256"
          )
        end

        def encrypt(plaintext, key:)
          salt = OpenSSL::Random.random_bytes(SALT_LENGTH)
          derived = derive_key(key, salt: salt)

          cipher = OpenSSL::Cipher::AES256.new(:GCM)
          cipher.encrypt
          iv = cipher.random_iv
          cipher.key = derived

          ciphertext = cipher.update(plaintext) + cipher.final
          tag = cipher.auth_tag(TAG_LENGTH)

          # Binary format: MAGIC(4) + VERSION(1) + SALT(32) + IV(12) + TAG(16) + CIPHERTEXT
          [MAGIC, FORMAT_VERSION].pack("a4C") + salt + iv + tag + ciphertext
        end

        def decrypt(data, key:)
          unless encrypted?(data)
            raise Kodo::Error, "Not a valid encrypted file (missing KODO header)"
          end

          _magic, version = data[0, 5].unpack("a4C")
          unless version == FORMAT_VERSION
            raise Kodo::Error, "Unsupported encryption format version: #{version}"
          end

          offset = MAGIC.bytesize + 1
          salt = data.byteslice(offset, SALT_LENGTH)
          offset += SALT_LENGTH
          iv = data.byteslice(offset, IV_LENGTH)
          offset += IV_LENGTH
          tag = data.byteslice(offset, TAG_LENGTH)
          offset += TAG_LENGTH
          ciphertext = data.byteslice(offset..)

          derived = derive_key(key, salt: salt)

          decipher = OpenSSL::Cipher::AES256.new(:GCM)
          decipher.decrypt
          decipher.iv = iv
          decipher.key = derived
          decipher.auth_tag = tag

          (decipher.update(ciphertext) + decipher.final).force_encoding("UTF-8")
        rescue OpenSSL::Cipher::CipherError
          raise Kodo::Error, "Decryption failed — wrong passphrase or corrupted data"
        end

        def encrypted?(data)
          return false if data.nil? || data.bytesize < HEADER_LENGTH
          data.byteslice(0, MAGIC.bytesize) == MAGIC
        end
      end
    end
  end
end
