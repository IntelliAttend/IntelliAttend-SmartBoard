import firebase_admin
from firebase_admin import credentials, firestore
import os

key_path = '/Users/balaseetharamanjaneyulu/Dev/IntelliAttend /IntelliAttend-Server/config/serviceAccountKey.json'
cred = credentials.Certificate(key_path)
if not firebase_admin._apps:
    firebase_admin.initialize_app(cred)
db = firestore.client()

print("--- Checking Wednesday slots for room_4208 ---")
slots = db.collection('timetable_slots').where('classroom_id', '==', 'room_4208').where('day_of_week', '==', 'Wednesday').get()
if slots:
    print(f"Found {len(slots)} slots for Wednesday")
    for slot in slots:
        print(f"  Slot: {slot.id} -> {slot.to_dict().get('subject_name')}")
else:
    print("No slots found for Wednesday in room_4208")

print("\n--- Listing ALL days present for room_4208 ---")
all_slots = db.collection('timetable_slots').where('classroom_id', '==', 'room_4208').get()
days = set()
for s in all_slots:
    days.add(s.to_dict().get('day_of_week'))
print(f"Days found: {days}")
