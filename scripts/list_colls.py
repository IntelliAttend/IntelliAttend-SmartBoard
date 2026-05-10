import firebase_admin
from firebase_admin import credentials, firestore
import os

key_path = '/Users/balaseetharamanjaneyulu/Dev/IntelliAttend /IntelliAttend-Server/config/serviceAccountKey.json'
cred = credentials.Certificate(key_path)
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)
db = firestore.client()

print("--- Listing Collections ---")
collections = db.collections()
for coll in collections:
    print(f"Collection: {coll.id}")
