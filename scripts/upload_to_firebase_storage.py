import os
import sys
from google.cloud import storage

def upload_apk():
    creds_path = r"D:\test app\AiMoneyManager\serviceAccountKey.json"
    apk_path = r"D:\test app\ai_money_manager_flutter\money_manager_major_v2.0.0.apk"
    destination_blob_name = "updates/money_manager_major_v2.0.0.apk"
    
    if not os.path.exists(creds_path):
        print(f"ERROR: Service account key not found at {creds_path}")
        return False
        
    if not os.path.exists(apk_path):
        print(f"ERROR: APK not found at {apk_path}")
        return False

    client = storage.Client.from_service_account_json(creds_path)
    
    # Check default bucket name from google-services.json
    bucket_names = [
        "ai-money-manager-c6a54.firebasestorage.app",
        "ai-money-manager-c6a54.appspot.com",
    ]
    
    target_bucket = None
    for b_name in bucket_names:
        try:
            b = client.get_bucket(b_name)
            target_bucket = b
            print(f"Connected to bucket: {b_name}")
            break
        except Exception as e:
            print(f"Bucket {b_name} check: {type(e).__name__} {e}")
            
    if target_bucket is None:
        print("\n[FIREBASE STORAGE ACTIVATION REQUIRED]")
        print("Firebase Storage has not yet been provisioned in the Firebase Console for project 'ai-money-manager-c6a54'.")
        print("To provision the free 5GB Spark plan storage bucket:")
        print("1. Open: https://console.firebase.google.com/project/ai-money-manager-c6a54/storage")
        print("2. Click 'Get started' and accept the default security rules.")
        print("3. As soon as 'Get started' completes, re-run this script to upload immediately!")
        return False

    print(f"Uploading {apk_path} to gs://{target_bucket.name}/{destination_blob_name} ...")
    blob = target_bucket.blob(destination_blob_name)
    blob.chunk_size = 5 * 1024 * 1024  # 5MB chunks
    blob.upload_from_filename(apk_path, content_type="application/vnd.android.package-archive")
    print(f"Upload complete: {destination_blob_name}")
    
    # Try to make public if bucket permissions allow ACLs
    try:
        blob.make_public()
        print(f"Public URL: {blob.public_url}")
    except Exception as e:
        print(f"Note on public ACL: {e} (Firebase Storage rules control access)")
        
    return True

if __name__ == "__main__":
    success = upload_apk()
    sys.exit(0 if success else 1)
