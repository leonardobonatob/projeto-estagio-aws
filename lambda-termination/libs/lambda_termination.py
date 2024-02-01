import ldap
import boto3
from botocore.exceptions import ClientError
import json
import os

dns_hostname = os.environ.get('DNS_HOSTNAME')
directory_name = os.environ.get('DIRECTORY_NAME')
directory_id = os.environ.get('DIRECTORY_ID')
secret_name = os.environ.get('SSM_AD_ADMIN')

def lambda_handler(event, context):
    # Retrieve the parameters from the event    
    hostname = dns_hostname.split(",")[0]
    workspace = event['detail']['requestParameters']['terminateWorkspaceRequests'][0]['workspaceId']
    hostnametwo = dns_hostname.split(",")[1]

    #get the Hostname via WorkSpaces API
    workspaces = boto3.client('workspaces')

    computer = workspaces.describe_workspaces(
    WorkspaceIds=[
        workspace,
    ])['Workspaces'][0]['ComputerName']

    #get the AD credentials in Secrets Manager
    # Create a Secrets Manager client
    region_name = "us-east-1"
    session = boto3.session.Session()
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
    username = str(scrt['username'])
    password = str(scrt['password'])
    
    print(f"Secret retrieved. Bind to LDAP server")
    
    # Bind to the LDAP server
    try:
        conn = ldap.initialize(f"ldap://{hostname}")
        bind = conn.simple_bind_s(username, password)
    except:
        try:
            print("First connection attempt with AD failed.")
            conn = ldap.initialize(f"ldap://{hostnametwo}")
            print("Initializing connection attempt with second host ip from Active Directory.")
            bind = conn.simple_bind_s(username, password)
        except:
            raise Exception("Can't contact LDAP server, connection wasnt succeeded.")

    print("Connection with Active Directory succeeded. Searching for computer object.")

    # Search for the computer object
    base_dn = f"DC={directory_name.split('.')[0]},DC={directory_name.split('.')[1]},DC={directory_name.split('.')[2]}"
    search_filter = f"(cn={computer})"
    search_scope = ldap.SCOPE_SUBTREE
    result = conn.search_s(base_dn, search_scope, search_filter)

    # Delete the computer object
    dn = result[0][0]
    if dn is None:
        raise Exception(f"Computer object {computer} not found in Active Directory.")
        
    print("Computer Found.")
    print(f"Deleting {computer} object from AD...")
    deletion = conn.delete_s(dn)
    if deletion is None:
        raise Exception(f"Can't delete computer object:{computer} from Active Directory. Check permissions or AD health status.")
    
    #Unbind from the LDAP server
    conn.unbind_s()
    
    return(computer)