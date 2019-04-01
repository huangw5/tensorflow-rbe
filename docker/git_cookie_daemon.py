#!/usr/bin/python
"""Background daemon to refresh OAuth access tokens.

In order to authenticate to Git-on-Borg via https, we must retrieve an OAuth 2
token, install it in a git "cookie jar", and configure git to use the cookie jar
when authenticating to https://*.googlesource.com. This tool does this and
remains running, refreshing the token before it expires.

Tokens are written to ~/.git-credential-cache/cookie.
Git config variable http.cookiefile is updated when this runs.
"""

import argparse
import cookielib
import json
import logging as pylog
import os
import subprocess
import sys
import time
import urllib2

from oauth2client.client import GoogleCredentials
from oauth2client.service_account import ServiceAccountCredentials

SCOPE = 'https://www.googleapis.com/auth/gerritcodereview'

REFRESH_SEC = 25  # seconds remaining when starting refresh
RETRY_INTERVAL_SEC = 5  # seconds between retrying a failed refresh

GITDIR = os.path.join(os.environ['HOME'], '.git-credential-cache')
DEFAULT_COOKIE_JAR = os.path.join(GITDIR, 'cookie')


def configure_git(cookie_jar):
  """Configure git to use the cookie jar for authentication."""
  if os.path.exists(GITDIR):
    os.chmod(GITDIR, 0700)
  else:
    os.mkdir(GITDIR, 0700)
  subprocess.call([
      'git', 'config', '--global',
      'http.cookiefile', cookie_jar
  ])


def acquire_token(keyfile_dict):
  """Retrieve an OAuth 2 access token."""
  if keyfile_dict is None:
    creds = GoogleCredentials.get_application_default().create_scoped(SCOPE)
  else:
    creds = ServiceAccountCredentials.from_json_keyfile_dict(
        keyfile_dict, SCOPE)
  pylog.info('Successfully acquired OAuth 2 token.')
  return creds.get_access_token()


def update_cookie(cookie_jar, access_token, expires):
  """Updates the cookie jar with the provided access token."""
  cj = cookielib.MozillaCookieJar(cookie_jar)

  for d in ['source.developers.google.com', '.googlesource.com']:
    cj.set_cookie(cookielib.Cookie(
        version=0,
        name='o',
        value=access_token,
        port=None,
        port_specified=False,
        domain=d,
        domain_specified=True,
        domain_initial_dot=d.startswith('.'),
        path='/',
        path_specified=True,
        secure=True,
        expires=expires,
        discard=False,
        comment=None,
        comment_url=None,
        rest=None))

  cj.save()
  pylog.info('Updated cookie jar: %s', cookie_jar)


def refresh_loop(keyfile_dict, cookie_jar, expires):
  while True:
    # Sleep until our refresh time, or every RETRY_INTERVAL_SEC in case the
    # server is slow to give us a new token and expiry.
    sleep_sec = max(expires - time.time() - REFRESH_SEC, RETRY_INTERVAL_SEC)
    pylog.info('Sleeping %d seconds.', sleep_sec)
    time.sleep(sleep_sec)

    # Get a new token, retrying on URLerror
    while True:
      try:
        token = acquire_token(keyfile_dict)
        break
      except urllib2.URLError:
        pylog.warning('URLError while retrieving credentials. Retrying...')
      time.sleep(RETRY_INTERVAL_SEC)

    # Update the Cookie Jar
    expires = time.time() + int(token.expires_in)
    update_cookie(cookie_jar, token.access_token, expires)


def main():
  p = argparse.ArgumentParser(description='Git cookie from JSON daemon')
  p.add_argument('-c', '--configure-git', action='store_true',
                 help='Configure git to use the cookie jar.')
  p.add_argument('-d', '--daemonize', action='store_true',
                 help='Fork and daemonize')
  p.add_argument('--pidfile',
                 help='Write a pidfile to this location.')
  p.add_argument('-j', '--json',
                 help='Path to Google Service Account JSON credentials file.')
  p.add_argument('--cookie-jar', default=DEFAULT_COOKIE_JAR,
                 help='File path to use for the git cookie jar.')

  args = p.parse_args()

  pylog.basicConfig(level=pylog.INFO)

  keyfile_dict = None
  if args.json:
    with open(args.json, 'r') as f:
      keyfile_dict = json.loads(f.read())

  if args.configure_git:
    configure_git(args.cookie_jar)

  token = acquire_token(keyfile_dict)
  expires = time.time() + int(token.expires_in)
  update_cookie(args.cookie_jar, token.access_token, expires)

  if args.daemonize:
    if not args.pidfile:
      pylog.error('Failed to daemonize: missing required "--pidfile" argument.')
      sys.exit(1)

    if os.fork() > 0:
      sys.exit(0)

    os.chdir('/')
    os.setsid()
    os.umask(0)

    pid = os.fork()
    if pid > 0:
      with open(args.pidfile, 'w') as f:
        f.write(str(pid))
      print '{progname} PID {pid}'.format(progname=sys.argv[0], pid=pid)
      sys.exit(0)

    refresh_loop(keyfile_dict, args.cookie_jar, expires)


if __name__ == '__main__':
  main()
