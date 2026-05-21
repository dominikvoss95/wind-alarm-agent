import boto3
import os
from dotenv import load_dotenv

# Load the keys from .env
load_dotenv()

def test_bedrock_connection():
    print("=== AWS Bedrock Connectivity Test ===")
    
    # Initialize the Bedrock Runtime client
    # It will automatically pick up AWS_ACCESS_KEY_ID etc. from the environment
    try:
        client = boto3.client(
            service_name='bedrock-runtime',
            region_name='eu-central-1'
        )
        
        # Try a tiny dummy call to Nova Lite
        # Just to see if we get an 'Access Denied' or a real response
        model_id = "amazon.nova-lite-v1:0"
        
        print(f"Connecting to model: {model_id}...")
        
        # We just send a tiny body
        body = '{"prompt": "Hi", "max_tokens": 1}'
        
        response = client.invoke_model(
            modelId=model_id,
            body=body
        )
        
        print("✅ SUCCESS: Connection to AWS Bedrock established!")
        print(f"Status Code: {response['ResponseMetadata']['HTTPStatusCode']}")
        
    except Exception as e:
        print("❌ FAILURE: Could not connect to AWS.")
        print(f"Error: {str(e)}")
        
        if "AccessDeniedException" in str(e):
            print("\nHint: Your keys work, but they don't have the permission for this model yet.")
        elif "InvalidClientTokenId" in str(e) or "SignatureDoesNotMatch" in str(e):
            print("\nHint: Check your Access Key and Secret Key in the .env file.")

if __name__ == "__main__":
    test_bedrock_connection()
