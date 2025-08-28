import boto3
import os
from PIL import Image
import io
import json

# Initialize clients outside handler for reuse
s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    # Log the incoming event
    print(f"Event received: {json.dumps(event)}")
    
    # Get the bucket and object key from the S3 event
    try:
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = event['Records'][0]['s3']['object']['key']
    except (KeyError, IndexError) as e:
        print(f"Error parsing event: {e}")
        return {'statusCode': 400, 'body': 'Invalid event structure'}
    
    # Only process common image types to avoid unnecessary processing
    image_extensions = ('.png', '.jpg', '.jpeg', '.gif', '.bmp')
    if not key.lower().endswith(image_extensions):
        print(f"Skipping non-image file: {key}")
        return {'statusCode': 200, 'body': 'Not an image file, skipping processing'}
    
    try:
        print(f"Processing image: {key}")
        
        # Download the image from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        image_content = response['Body'].read()
        
        # Process the image
        image = Image.open(io.BytesIO(image_content))
        
        # Create thumbnail (small size for free tier optimization)
        image.thumbnail((150, 150))  # Smaller size to reduce processing time/cost
        
        # Convert to bytes
        in_mem_file = io.BytesIO()
        
        # Convert format to JPEG for smaller size if original was different
        if image.format != 'JPEG':
            image = image.convert('RGB')
            save_format = 'JPEG'
        else:
            save_format = image.format
            
        image.save(in_mem_file, format=save_format, optimize=True, quality=85)
        in_mem_file.seek(0)
        
        # Upload processed image to destination bucket
        destination_bucket = os.environ['DESTINATION_BUCKET']
        new_key = f"thumbnails/{os.path.splitext(key)[0]}.jpg"
        
        s3.put_object(
            Bucket=destination_bucket,
            Key=new_key,
            Body=in_mem_file,
            ContentType="image/jpeg",
            StorageClass='STANDARD_IA'  # Lower storage cost for processed images
        )
        
        print(f"Successfully processed {key} -> {new_key}")
        
        # Send success notification (only for demonstration, can be disabled to save SNS costs)
        if os.environ.get('SEND_NOTIFICATIONS', 'false').lower() == 'true':
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject='Image Processing Successful',
                Message=f"Image {key} was successfully processed and saved to {destination_bucket}/{new_key}"
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Image processed successfully',
                'original_key': key,
                'processed_key': new_key
            })
        }
        
    except Exception as e:
        error_msg = f"Error processing image {key}: {str(e)}"
        print(error_msg)
        
        # Send error notification only for critical errors
        if os.environ.get('SEND_NOTIFICATIONS', 'false').lower() == 'true':
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject='Image Processing Failed',
                Message=error_msg
            )
            
        # Re-raise the exception to utilize the Dead Letter Queue
        raise e