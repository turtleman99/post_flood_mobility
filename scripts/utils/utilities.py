import os
import time
import random
import json
import shutil
import pickle


def sleep_(t=1):
    if random.random() > 0.95:
        t = t * random.uniform(0.5, 2)
        # print(f"Sleeping for {t} seconds...")
        time.sleep(t)

# save obj to pkl file
def save_pkl(obj, filepath):
    with open(filepath, 'wb') as f:
        pickle.dump(obj, f)

# read pkl file to obj
def read_pkl(filepath):
    with open(filepath, 'rb') as f:
        obj = pickle.load(f)
    return obj


# save obj to json file
def save_json(obj, filepath):
    with open(filepath, 'w') as f:
        json.dump(obj, f)

# read json file to obj
def read_json(filepath):
    with open(filepath, 'r') as f:
        obj = json.load(f)
    return obj


def ensure_path(path, remove=False):
    basename = os.path.basename(path.rstrip('/'))
    if os.path.exists(path):
        if remove and (basename.startswith('_')
                       or input('{} exists, remove? ([y]/n): '.format(path)) != 'n'):
            shutil.rmtree(path)
            os.makedirs(path)
    else:
        os.makedirs(path)