import time
import os
import datetime
date = datetime.datetime.now().strftime("%Y_%m_%d")
mz = 'Backup_log'
w = ('\n')
d = ('---------------------------------------------------------------------------------------------')
dz = "Logsswitches-config/"
hz = ('log')
RETENTION_DAYS = 14
class log:
    @staticmethod
    def logs(messages):
        json_text = {
            "msgtype": "text",
            "text": {
                "content": messages,

            },
        }


        pathway = dz

        backup_folder = os.path.join(pathway)
        output = messages
        if not os.path.exists(backup_folder):
            os.makedirs(backup_folder)
        backup_file = os.path.join(backup_folder, f"{mz}{date}.{hz}")
        with open(backup_file, "a") as f:
            f.write(str(output))
            f.write(w)
            f.write(w)
            f.write(d)
            f.write(w)
            f.write(w)

        # Rotar logs simples: borrar archivos más antiguos que RETENTION_DAYS
        try:
            cutoff = time.time() - (RETENTION_DAYS * 86400)
            for fname in os.listdir(backup_folder):
                fpath = os.path.join(backup_folder, fname)
                try:
                    if os.path.isfile(fpath) and os.path.getmtime(fpath) < cutoff:
                        os.remove(fpath)
                except Exception:
                    continue
        except Exception:
            pass


