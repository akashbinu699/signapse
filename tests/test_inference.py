import base64
import json
import os
import time
from google.oauth2 import service_account
from google.api_core.client_options import ClientOptions
from google.cloud import aiplatform_v1


PROJECT_ID = os.environ["GCP_PROJECT"]
LOCATION = os.environ.get("GCP_REGION", "us-central1")
ENDPOINT_NAME = os.environ["VERTEX_ENDPOINT_ID"]  # e.g. "12345678901"
PROMPT = "a futuristic city floating in the clouds"


def get_endpoint_client():
    creds_json = base64.b64decode(os.environ["GCP_SERVICE_ACCOUNT_KEY"]).decode()
    credentials = service_account.Credentials.from_service_account_info(
        json.loads(creds_json)
    )
    
    client_options = ClientOptions(api_endpoint=f"{LOCATION}-aiplatform.googleapis.com")
    return aiplatform_v1.PredictionServiceClient(
        client_options=client_options, credentials=credentials
    )


def test_inference():
    client = get_endpoint_client()

    instance = {"prompt": PROMPT}
    request = aiplatform_v1.PredictRequest(
        endpoint=f"projects/{PROJECT_ID}/locations/{LOCATION}/endpoints/{ENDPOINT_NAME}",
        instances=[instance]
    )

    print("Running inference request...")

    response = client.predict(request=request)

    assert response, "No response from endpoint"
    assert "predictions" in response._pb, "Missing predictions field"

    prediction = response._pb.predictions[0]

    # Expect base64 image or URL depending on your response format
    assert (
        "image" in prediction or "url" in prediction
    ), "Prediction format missing `image` or `url` field"

    print("Inference successful!")
    print("Returned prediction:", prediction)


if __name__ == "__main__":
    # Allow warmup time if endpoint was cold-started
    time.sleep(5)
    test_inference()
