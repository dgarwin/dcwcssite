import os, json
import requests
from googleapiclient.discovery import build
from google.auth import default
from google.cloud import storage
import functions_framework
import google.auth

def get_running_sa():
    METADATA_URL = (
        'http://metadata.google.internal/computeMetadata/v1/'
        'instance/service-accounts/default/email'
    )
    headers = {'Metadata-Flavor': 'Google'}
    try:
        resp = requests.get(METADATA_URL, headers=headers, timeout=2)
        resp.raise_for_status()
        return resp.text
    except Exception as e:
        return f"error fetching SA: {e}"

@functions_framework.http
def hello_http(request):
    """HTTP Cloud Function.
    Args:
        request (flask.Request): The request object.
        <https://flask.palletsprojects.com/en/1.1.x/api/#incoming-request-data>
    Returns:
        The response text, or any set of values that can be turned into a
        Response object using `make_response`
        <https://flask.palletsprojects.com/en/1.1.x/api/#flask.make_response>.
    """
    process_spreadsheets()
    return 'success'

# ← Set these in Cloud Run’s environment variables:
FOLDER_ID   = '1aF_JZ7PEshEHMOwW2cybPLlPuTpClicx'    # e.g. "1aF_JZ7PEshEHMOwW2cybPLlPuTpClicx"
BUCKET_NAME = 'dcwcs'  # e.g. "dcwcs"
OUTPUT_FILE = 'events.json'

# On Cloud Run, ADC will pick up the attached service account.
creds, project        = default()
print(f"Currently running in project: {project}")
drive_service   = build('drive', 'v3', credentials=creds)
sheets_service  = build('sheets', 'v4', credentials=creds)
storage_client  = storage.Client(credentials=creds)

def process_spreadsheets():
    print(get_running_sa())
    # 1) list all Sheets in the folder
    q = f"'{FOLDER_ID}' in parents and mimeType='application/vnd.google-apps.spreadsheet'"
    files = drive_service.files().list(q=q, fields='files(id,name)').execute().get('files', [])

    events = []
    for f in files:
        sid = f['id']
        data = sheets_service.spreadsheets().values().get(
            spreadsheetId=sid,
            range='Sheet1'
        ).execute().get('values', [])
        if len(data) < 2:
            continue

        headers = [h.strip() for h in data[0]]
        for row in data[1:]:
            # zip headers → row, fill missing with ''
            entry = { 
                headers[i]: (row[i] if i < len(row) else '') 
                for i in range(len(headers)) 
            }
            events.append({
                "name":             entry.get('Name',''),
                "location":         entry.get('Location',''),
                "date":             entry.get('Date',''),
                "time":             entry.get('Time',''),
                "has_intro_lesson": entry.get('Has_Intro_Lesson',''),
                "image_url":        entry.get('Image_URL','')
            })

    # 2) write JSON to GCS
    bucket = storage_client.bucket(BUCKET_NAME)
    blob   = bucket.blob(OUTPUT_FILE)
    blob.upload_from_string(
        json.dumps(events, indent=2),
        content_type='application/json'
    )

    return
