# MFA Locker for Flutter

**MFA Locker** is a library for securely storing sensitive data (such as passwords, tokens, or cryptocurrency wallet seed phrases) on the client side.  
All data is stored in a single JSON file in encrypted form. Writing to the file is atomic.

---

### Used Algorithms

- **HMAC + SHA-256** – allows you to verify that the data in storage hasn’t been modified since the last access.  
- **AES-GCM** – the main algorithm used for symmetric encryption of stored data.  
- **PBKDF2** – a method for deriving a signature from a password and salt. In practice, it converts a password and salt into a single key by repeatedly applying a hash function.

---

### Structure of the Saved File

```json
{
    "entries": [ 
        {
            "id": "BASE64...",      // entry identifier
            "meta": "BASE64...",    // key (encrypted)
            "value": "BASE64..."    // value (encrypted)
        }
    ],
    "masterKey": {
        "wraps": [
            { "origin": "pwd", "data": "BASE64..." }, // master key encrypted with password
            { "origin": "bio", "data": "BASE64..." }  // master key encrypted with biometrics
        ]
    },
    "hmacKey": "BASE64...",        // HMAC key encrypted with the master key
    "hmacSignature": "BASE64...",  // HMAC result over the file excluding hmacSignature itself
    "salt": "BASE64..."            // salt for the PBKDF2 algorithm
}
```

---

## Algorithm for Creating the Storage

1. Generate a **master key (MK)** using `CryptographyUtils.generateAESKey()`.
2. Each authentication method acts as a “wrapper” over the MK. We can encrypt the MK using:
   - **Password:**
     1. Ask the user for a password.  
     2. Generate salt with `CryptographyUtils.generateSalt()`. Derive a password key (PK) using PBKDF2 via `CryptographyUtils.deriveKeyFromPassword(password, salt)`.  
     3. Convert the salt to base64 and store it in the storage under the `"salt"` key.  
     4. Encrypt the MK using AES-GCM and the PK (`CryptographyUtils.encrypt`).  
     5. Convert the encrypted MK to base64 and create a `Wrap` object containing it.  

     ```json
     { 
        "origin": "pwd",
        "data": "BASE64..." // encrypted master key
     }
     ```

   - **Biometrics (via secure_mnemonic plugin):**
     1. Take a key tag (id), e.g. `"MASTER_KEY"`, and generate a private key in the TPM using `generateKey(tag)`.  
     2. Use `encrypt(tag, data)` to encrypt the unencrypted MK with the tag key.  
     3. Convert the encrypted MK to base64 and create a `Wrap` object.  

     ```json
     { 
        "origin": "bio",
        "data": "BASE64..." // encrypted master key
     }
     ```

3. After encryption, we obtain a **WrappedKey** object. The `id` is used to identify the key and as a tag for biometric authentication. Add the WrappedKey to storage:

    ```json
    {
        "id": "MASTER_KEY",
        "wraps": [
            { "origin": "pwd", "data": "BASE64..." },
            { "origin": "bio", "data": "BASE64..." }
        ]
    }
    ```

4. Add data entries to the storage. Each key and value is encrypted using the MK:

    ```json
    {
        "digest": "BASE64...", // entry identifier
        "key": "BASE64...",    // encrypted key
        "value": "BASE64...",  // encrypted value
        "keyId": "BASE64..."   // id of the key used for encryption
    }
    ```

5. Generate an **HMAC key** (without input data) using `CryptographyUtils.generateAESKey()`. Encrypt it with the MK and store it:

    ```json
    "hmacKey": "BASE64..." // HMAC key encrypted with master key
    ```

6. Compute **hmacSignature** over the entire JSON (excluding the hmacSignature field) using `CryptographyUtils.authenticateHmac`.  
7. Add the hmacSignature to the storage:

    ```json
    "hmacSignature": "BASE64..." // HMAC result excluding hmacSignature itself
    ```

8. Save the JSON file on the device.

---

## Algorithm for Retrieving Data

1. Load the JSON file from the device.  
2. Decrypt the MK using password or biometrics:
   - **Password authentication:**
     1. Request password.  
     2. Decode the encrypted MK from base64 to `Uint8List`.  
     3. Get salt from `json["salt"]`. Derive the password key (PK) using PBKDF2 (`CryptographyUtils.deriveKeyFromPassword`).  
     4. Decrypt the MK using AES-GCM (`CryptographyUtils.decrypt`).  
   - **Biometric authentication:**
     1. Request biometric verification.  
     2. Decode the encrypted MK from base64 to `Uint8List`.  
     3. Retrieve the master key tag (id) from `WrappedKey.id`.  
     4. Decrypt the MK using `secureMnemonic.decrypt(tag, data)`.  

3. Call `CryptographyUtils.authenticateHmac` on the JSON body (excluding `hmacSignature`). Compare the result with the stored `hmacSignature`.  
4. If they don’t match, throw an error indicating that the storage is corrupted.  
5. Decrypt the required data using the MK.

---

## Other Security Tools

### ErasableByteArray

A data structure that contains `Uint8List bytes` and an `erase` method.  
The `erase` method sets all bytes to zero and then nullifies the reference (removes the object).

**Advantages:**
- Quickly removes sensitive data from memory.  
- Independent of garbage collection.

---

### ErasableByteArrayPool

Contains a set of `ErasableByteArray` objects.  
Allows tracking of long-lived objects and issues warnings for debugging purposes.

---

### Auto-Locking Storage

The storage can automatically lock (erasing all secrets from RAM) after a certain period of inactivity.  
The auto-lock timer resets with every screen tap.
