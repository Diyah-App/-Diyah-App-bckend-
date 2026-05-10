import firebase_admin
from firebase_admin import remote_config

with open("rc_dir.txt", "w") as f:
    f.write(str(dir(remote_config)))
