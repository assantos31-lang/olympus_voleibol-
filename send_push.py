import json
import requests
from google.oauth2 import service_account
from google.auth.transport.requests import Request

SERVICE_ACCOUNT_FILE = "firebase-service-account.json"
PROJECT_ID = "olympus-voleibol"

DEVICE_TOKEN = "d31Y2CwmRVe1WhVhYwMN7u:APA91bETpV9Wah4jJ7EGYvGONqj1SvSYkvWihCqdKKB9-UdnpTt4QtcTfRD0-CK7FshAivu6MQ0p1CjrxG3TyLn3jPHiybx2JgQjVZ8g71JtKrfT67ZLdfw"

SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]

def get_access_token():
    credentials = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE,
        scopes=SCOPES,
    )
    credentials.refresh(Request())
    return credentials.token

def send_push():
    access_token = get_access_token()

    url = f"https://fcm.googleapis.com/v1/projects/{PROJECT_ID}/messages:send"

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json; UTF-8",
    }

    body = {
        "message": {
            "token": DEVICE_TOKEN,
            "notification": {
                "title": "Olympus Voleibol",
                "body": "Teste direto no iPhone"
            },
            "apns": {
                "headers": {
                    "apns-priority": "10"
                },
                "payload": {
                    "aps": {
                        "alert": {
                            "title": "Olympus Voleibol",
                            "body": "Teste direto no iPhone"
                        },
                        "sound": "default",
                        "badge": 1
                    }
                }
            }
        }
    }

    response = requests.post(url, headers=headers, data=json.dumps(body))
    print("STATUS:", response.status_code)
    print("RESPOSTA:", response.text)

if __name__ == "__main__":
    send_push()