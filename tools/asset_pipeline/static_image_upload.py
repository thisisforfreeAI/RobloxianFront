"""Owner-run resumable Open Cloud Image uploader. Dry-run unless --execute is supplied.
Credentials are read from ROBLOX_ASSET_API_KEY (or --key-env); never put keys in manifests.
"""
import argparse,hashlib,json,os,re,time,urllib.request,uuid
from pathlib import Path

BASE='https://apis.roblox.com/assets/v1/'
def request(url,key,data=None,content_type=None):
    headers={'x-api-key':key}
    if content_type:headers['Content-Type']=content_type
    req=urllib.request.Request(url,data=data,headers=headers,method='POST'if data else 'GET')
    with urllib.request.urlopen(req,timeout=30)as response:return json.load(response)
def upload(path,creator,key,send=request,sleep=time.sleep,operation=None,on_operation=None):
    boundary='RobloxianFront'+uuid.uuid4().hex
    metadata={'assetType':'Image','displayName':path.stem[:100],'description':'RobloxianFront static atlas','creationContext':{'creator':creator,'expectedPrice':0}}
    body=(f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n'+json.dumps(metadata)+f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="{path.name}"\r\nContent-Type: image/png\r\n\r\n').encode()+path.read_bytes()+f'\r\n--{boundary}--\r\n'.encode()
    if operation:op=operation
    else:op=send(BASE+'assets',key,body,'multipart/form-data; boundary='+boundary).get('path','')
    if not re.fullmatch(r'operations/[A-Za-z0-9_-]+',op):raise ValueError('unexpected upload operation path')
    if on_operation:on_operation(op)
    for _ in range(60):
        result=send(BASE+op,key)
        if result.get('done'):
            if 'error'in result:raise RuntimeError('Roblox rejected upload; inspect operation '+op)
            response=result.get('response',{});asset=str(response.get('assetId',''))
            if not re.fullmatch(r'[1-9]\d{0,19}',asset):raise ValueError('upload returned no Image ID')
            if response.get('assetType')not in (None,'Image','ASSET_TYPE_IMAGE'):raise ValueError('response is not an Image asset; do not import its ID')
            return asset
        sleep(2)
    raise TimeoutError('upload still processing: '+op+'; rerun to resume its saved operation')
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('package',type=Path);c=p.add_mutually_exclusive_group();c.add_argument('--user-id');c.add_argument('--group-id');p.add_argument('--key-env',default='ROBLOX_ASSET_API_KEY');p.add_argument('--execute',action='store_true');a=p.parse_args()
    root=a.package.resolve();manifest=json.loads((root/'manifest.json').read_text(encoding='utf-8'));ids_path=root/'image_ids.json';ids=json.loads(ids_path.read_text(encoding='utf-8'))
    op_path=root/'operations.json';operations=json.loads(op_path.read_text(encoding='utf-8'))if op_path.exists()else{}
    if manifest.get('assetType')!='Image':raise ValueError('expected Image package')
    pending=[entry for entry in manifest['entries']if 'aliasOf'not in entry and not ids.get(entry['key'])]
    print(f'{len(pending)} canonical PNGs pending; '+('upload enabled'if a.execute else 'dry-run, no network requests'))
    if not a.execute:return
    creator_id=a.user_id or a.group_id
    if not creator_id or not re.fullmatch(r'[1-9]\d*',creator_id):raise ValueError('supply the owning --user-id or --group-id')
    key=os.environ.get(a.key_env)
    if not key:raise ValueError('set the requested API-key environment variable locally')
    creator={'userId'if a.user_id else 'groupId':creator_id}
    for entry in pending:
        path=(root/entry['file']).resolve()
        if root not in path.parents or hashlib.sha256(path.read_bytes()).hexdigest()!=entry['sha256']:raise ValueError('package image changed or escapes package')
        previous=operations.get(entry['key'])
        if previous and previous['sha256']!=entry['sha256']:raise ValueError('pending upload belongs to a changed PNG; inspect its operation before uploading again')
        def save_operation(op):
            operations[entry['key']]={'path':op,'sha256':entry['sha256']}
            temp=op_path.with_suffix('.json.tmp');temp.write_text(json.dumps(operations,indent=2)+'\n',encoding='utf-8');temp.replace(op_path)
        ids[entry['key']]=upload(path,creator,key,operation=previous['path']if previous else None,on_operation=save_operation)
        temporary=ids_path.with_suffix('.json.tmp');temporary.write_text(json.dumps(ids,indent=2)+'\n',encoding='utf-8');temporary.replace(ids_path)
        operations.pop(entry['key'],None);op_path.write_text(json.dumps(operations,indent=2)+'\n',encoding='utf-8')
        print('Uploaded',entry['key'])
    print('Run static_image_package.py import to install the returned Image IDs. Nothing was published to a place.')
if __name__=='__main__':main()
