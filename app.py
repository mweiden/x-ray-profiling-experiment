import json
import os
import boto3
import codecs
from botocore.exceptions import ClientError
from aws_xray_sdk.core import xray_recorder, patch
from aws_xray_sdk.core.context import Context
from aws_xray_sdk.ext.flask.middleware import XRayMiddleware
from flask import request, make_response
from flask_lambda import FlaskLambda

patch(('boto3',))

xray_recorder.configure(
    service='x-ray-profiling-experiment',
    dynamic_naming='*.execute-api.us-east-1.amazonaws.com/test*',
    context=Context()
)

s3_client = boto3.resource('s3')

app = FlaskLambda(__name__)
XRayMiddleware(app, xray_recorder)

HOST = os.environ.get('HOST')
PORT = int(os.environ.get('PORT')) if 'PORT' in os.environ else None
bucket = 'logs-test-861229788715'


# health check endpoint
@app.route('/health')
def health():
    return "OK"


# cache endpoint
@app.route('/cache/<key>', methods=['GET', 'PUT', 'DELETE'])
def stuff(key):
    if request.method == 'PUT':
        xray_recorder.begin_subsegment('encryption')
        data = codecs.encode(request.data.decode('utf-8'), 'rot_13')
        xray_recorder.end_subsegment()
        app.logger.info('Setting \"{}\"=\"{}\"'.format(key, data))
        s3_client.Object(bucket, 'cache/' + key).put(Body=data)
        body = json.dumps({'status': 'OK'})
        status = 201
    elif request.method == 'DELETE':
        obj = s3_client.Object(bucket, 'cache/' + key)
        obj.delete()
        body = ''
        status = 204
    elif request.method == 'GET':
        try:
            app.logger.info('Getting \"{}\"'.format(key))
            obj = s3_client.Object(bucket, 'cache/' + key)
            body = obj.get()['Body'].read().decode('utf-8')
            xray_recorder.begin_subsegment('decryption')
            body = codecs.decode(body, 'rot_13')
            xray_recorder.end_subsegment()
            status = 200
        except ClientError as ex:
            app.logger.exception('Error', ex)
            if ex.response['Error']['Code'] == 'NoSuchKey':
                status = 204
                body = ''
            else:
                raise ex
    else:
        body = json.dumps({'status': 'Method Not Supported'})
        status = 406
    app.logger.info('Status {}, Body \"{}\"'.format(status, body))
    return make_response(body, status)


if __name__ == '__main__':
    if HOST and PORT:
        app.run(host=HOST, port=PORT, debug=True)
    else:
        app.run(debug=True)
