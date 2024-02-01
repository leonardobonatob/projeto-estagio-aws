import time
import ldap
import ldap.modlist as modlist
import boto3
import random
from boto3 import resource
from botocore.exceptions import ClientError
import json
import os
import zipfile
import gzip
import re, string
import io 
from io import BytesIO
from datetime import datetime
import base64, sys

dns_hostname = os.environ.get('DNS_HOSTNAME')
directory_id = os.environ.get('DIRECTORY_ID')
directory_name = os.environ.get('DIRECTORY_NAME')
secret_name = os.environ.get('SSM_AD_ADMIN')
s3 = boto3.client('s3')
session = boto3.session.Session()
workspaces = boto3.client('workspaces')
kms = boto3.client('kms')

def lambda_handler(event, context):

    # Retrieve the parameters from the event
    hostname = dns_hostname.split(",")[0]
    bucketname = event['detail']['bucket']['name']
    hostnametwo = dns_hostname.split(",")[1]
    object_key = event.get('detail').get('object').get('key')
    #get the AD credentials in Secrets Manager
    region_name = "us-east-1"

    # Create a Secrets Manager client
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        # For a list of exceptions thrown, see
        # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
        raise e

    # Decrypts secret using the associated KMS key.
    secret = get_secret_value_response['SecretString']
    scrt = json.loads(secret)
    username_bind = str(scrt['username'])
    password_bind = str(scrt['password'])
    
    print(f"Secret retrieved. Bind to LDAP server")

    # Bind to the LDAP server
    try:
        conn = ldap.initialize(f"ldap://{hostname}")
        conn.protocol_version = 3
        conn.set_option(ldap.OPT_REFERRALS, 0)
        conn.set_option(ldap.OPT_X_TLS_NEWCTX, 0)
        conn.simple_bind_s(username_bind, password_bind)
    except:
        try:
            print("First connection attempt with AD failed.")
            conn = ldap.initialize(f"ldap://{hostnametwo}")
            print("Initializing connection attempt with second host ip from Active Directory.")
            bind = conn.simple_bind_s(username_bind, password_bind)
        except:
            raise Exception("Can't contact LDAP server, connection wasnt succeeded.")

    print("Connection with Active Directory succeeded.")

    result = s3.download_file(bucketname, object_key, '/tmp/' + object_key)

    # REGEX Information
    data = ""
    allowed_punctuation = string.punctuation.replace('"', '').replace("'", '')
    with open ('/tmp/' + object_key,"r") as file:
        data = file.read().replace("﻿", " ")
        pattern = re.compile(f'[^{re.escape(string.ascii_letters + string.digits + allowed_punctuation)}]')
        lst = data.split('\n')
        transformed_text = []
        for item in lst:
            if item != "":
                transformed_text.append(pattern.sub('', item))

    responsekms = kms.describe_key(
        KeyId='alias/aws/workspaces'
    )

    ##Create a User in AD   
    company = object_key.split('.')[0]
    for i in transformed_text:
        user_attrs = {}    
        try:
            name = i.split(',')[0].replace("\"","")
        except:
            name = ''.join(random.sample(company,len(company))) + random.choice(["1","2","3","4","5","6","7","8","9"]) + random.choice(["1","2","3","4","5","6","7","8","9"])
            print("Using randomized values for user name")
        try:    
            first_name = name.split(' ')[0]
            last_name = name.split(' ')[1]
            curso = i.split(',')[1]
            ano = i.split(',')[2]
            username = first_name[0:7] + last_name[0:1] + random.choice(["1","2","3","4","5","6","7","8","9"])
        except:
            last_name = name[5:]
            first_name = name[:5]
            username = name[0:9] + random.choice(["1","2","3","4","5","6","7","8","9"])
            
        password = "123"+ username.replace("a",'').replace("e",'').replace("i",'').replace("o",'').replace("u",'') + username[0:2].upper() + "!"

        user_principal_name = f'{username}@{directory_name.split(".")[0]}.{directory_name.split(".")[   1]}.{directory_name.split(".")[2]}'
        #sam_account_name = directory_name.split(".")[0] + f"\\{username}"
        sam_account_name = username
        print(f"samAccountName:{sam_account_name} \n userPrincipalName:{user_principal_name}" )
        base_dn = f"OU=Users,OU={directory_name.split('.')[0]},DC={directory_name.split('.')[0]},DC={directory_name.split('.')[1]},DC={directory_name.split('.')[2]}"
        #base_dn = f"OU=Users,DC={directory_name.split('.')[0]},DC={directory_name.split('.')[1]},DC={directory_name.split('.')[2]}"
        user_dn = 'CN=' + username + ',' + base_dn

        print("without uid,with upn and with sam")
        user_attrs['objectclass'] = [b'top', b'person', b'organizationalPerson', b'user']
        #user_attrs['uid'] = [username.encode('utf-8')]
        user_attrs['cn'] = [username.encode('utf-8')]
        user_attrs['givenName'] =[first_name.encode('utf-8')]
        user_attrs['sn'] = [last_name.encode('utf-8')]
        user_attrs['displayName'] = [name.encode('utf-8')]
        user_attrs['userAccountControl'] = [b"514"]
        user_attrs['mail'] = [user_principal_name.encode('utf-8')]
        #user_attrs['userPassword'] = [password.encode('utf-8')]
        #user_attrs['primaryGroupID'] = [b'513']
        user_attrs['userPrincipalName'] = [user_principal_name.encode('utf-8')]
        user_attrs['sAMAccountName'] = [sam_account_name.encode('utf-8')]
        user_ldif = modlist.addModlist(user_attrs)

        print(user_dn)
        result = conn.add_s(user_dn, user_ldif) 
        print("User Added")
        time.sleep(1)

        #unicode_pass = '\"' + password + '\"'
        #password_value = unicode_pass.encode('utf-16-le')
        #add_pass = [(ldap.MOD_REPLACE, 'unicodePwd', [password_value])]

        # 512 will set user account to enabled
        #mod_acct = [(ldap.MOD_REPLACE, 'userAccountControl', '512'.encode('utf-8'))]

        #conn.modify_s(user_dn,[(ldap.MOD_ADD, 'userPassword', [password.encode('utf-8')])])
        #conn.modify_s(user_dn, add_pass)

        client = boto3.client('ds', region_name=region_name)
        client.reset_user_password(
            DirectoryId=directory_id,
            UserName=username,
            NewPassword=password
        )
        print("User Added")

        #conn.modify_s(user_dn, mod_acct)
        ##Create WorkSpaces Computer inside directoryID
        ##The UserName of the user for the WorkSpace. This user name must exist in the Directory Service directory for the WorkSpace.

        wsresult = workspaces.create_workspaces(
        Workspaces=[
            {
                'DirectoryId': directory_id,
                'UserName': username,
                'BundleId': 'wsb-gk1wpk43z',
                'VolumeEncryptionKey': responsekms['KeyMetadata']['Arn'],
                'UserVolumeEncryptionEnabled': True,
                'RootVolumeEncryptionEnabled': True,
                'WorkspaceProperties': {
                    'RunningMode': 'AUTO_STOP',
                    'RunningModeAutoStopTimeoutInMinutes': 240,
                    'RootVolumeSizeGib': 80,
                    'UserVolumeSizeGib': 50 ,
                    'ComputeTypeName': 'STANDARD',
                    'Protocols': [
                        'WSP',
                    ]
                },
            },
        ])
        print(wsresult)
        print("WorkSpaces criada para o usuário " + username + ", " + password)

    print("Login será feito pelos usuários através do domínio " + directory_name.split(".")[1])