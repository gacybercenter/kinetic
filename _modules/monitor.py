import json
import logging
import requests

log = logging.getLogger(__name__)

__virtualname__ = 'monitor'

def __virtual__():
    return __virtualname__

def rest_login(username, password, url):
    try:
        login = requests.post(
                    f'https://{url}:8000/login',
                    verify=False,
                    json={
                        'username':username,
                        'password':password,
                        'eauth':'pam'
                    }
                )
        print(login)
        token = json.loads(login.text)["return"][0]["token"]
        print(token)
        return token
    except Exception as e:
        log.error("Unable to authenticate foruse %s: %s", username, e)
        return False

def gather_jobs(username, password, url):
    try:
        token = rest_login(username, password, url)
        lease= requests.post(
                    f'https://{url}:8000/',
                    verify=False,
                    headers={
                        'X-Auth-Token':token
                    },
                    json=[
                        {
                        'client': 'local',
                        'fun': 'jobs.list_jobs'
                        }
                    ]
                )
        print (lease)
        jobs = json.loads(lease.text)
        print(jobs)
        return jobs
    except Exception as e:
        log.error("Unable to execute: %s", e)
        return False