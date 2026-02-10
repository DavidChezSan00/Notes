import requests

api_url_backup = 'https://X.X.X.X:12443/api/v2/monitor/system/config/backup?scope=global'
api_token = '9kQbppm3r54Nyjy7kb6bQxGyQhbNG7'
output_file = "backup_config_quincy.conf"

headers = {
    'Authorization': f'Bearer {api_token}'
}

requests.packages.urllib3.disable_warnings()

response_backup = requests.get(api_url_backup, headers=headers, verify=False)

if response_backup.status_code == 200:
    with open(output_file, "w") as file:
        file.write(response_backup.text)
    print(f"Respaldo guardado correctamente en {output_file}")
else:
    print("Error al obtener el respaldo.")
    print("Código de respuesta:", response_backup.status_code)
    print("Contenido recibido:", response_backup.text)
