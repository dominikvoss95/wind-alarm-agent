import firebase_admin
from firebase_admin import credentials, firestore
from wind_alarm.config import config

cred = credentials.Certificate(config.FIREBASE_CREDENTIALS_PATH)
firebase_admin.initialize_app(cred)
db = firestore.client()

docs = db.collection('latest_measurements').stream()
for doc in docs:
    print(f'{doc.id} => {doc.to_dict()}')
