# Copyright 2010 Jacob Kaplan-Moss
# Copyright 2011 OpenStack Foundation
# Copyright 2012 Grid Dynamics
# Copyright 2013 OpenStack Foundation
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import errno
import fcntl
import os
from oslo_log import log as logging
import select
import signal
import six
import six.moves.urllib.parse as urlparse
import socket
import struct
import sys
import termios
import time
import tty
import websocket

from zunclient.common.apiclient import exceptions as acexceptions
from zunclient.common.websocketclient import exceptions

LOG = logging.getLogger(__name__)

DEFAULT_API_VERSION = '1'
DEFAULT_ENDPOINT_TYPE = 'publicURL'
DEFAULT_SERVICE_TYPE = 'container'


class BaseClient(object):

    def __init__(self, zunclient, url, id, escape='~',
                 close_wait=0.5):
        self.url = url
        self.id = id
        self.escape = escape
        self.close_wait = close_wait
        self.cs = zunclient

    def connect(self):
        raise NotImplementedError()

    def fileno(self):
        raise NotImplementedError()

    def send(self, data):
        raise NotImplementedError()

    def recv(self):
        raise NotImplementedError()

    def tty_resize(self, height, width):
        """Resize the tty session

        Get the client and send the tty size data to zun api server
        The environment variables need to get when implement sending
        operation.
        """
        raise NotImplementedError()

    def start_loop(self):
        self.poll = select.poll()
        self.poll.register(sys.stdin,
                           select.POLLIN | select.POLLHUP
                           | select.POLLPRI | select.POLLNVAL)
        self.poll.register(self.fileno(),
                           select.POLLIN | select.POLLHUP |
                           select.POLLPRI | select.POLLNVAL)

        self.start_of_line = False
        self.read_escape = False
        with WINCHHandler(self):
            try:
                self.setup_tty()
                self.run_forever()
            except socket.error as e:
                raise exceptions.ConnectionFailed(e)
            except websocket.WebSocketConnectionClosedException as e:
                raise exceptions.Disconnected(e)
            finally:
                self.restore_tty()

    def run_forever(self):
        LOG.debug('starting main loop in client')
        self.quit = False
        quitting = False
        when = None

        while True:
            try:
                for fd, event in self.poll.poll(500):
                    if fd == self.fileno():
                        self.handle_socket(event)
                    elif fd == sys.stdin.fileno():
                        self.handle_stdin(event)
            except select.error as e:
                # POSIX signals interrupt select()
                no = e.errno if six.PY3 else e[0]
                if no == errno.EINTR:
                    continue
                else:
                    raise e

            if self.quit and not quitting:
                LOG.debug('entering close_wait')
                quitting = True
                when = time.time() + self.close_wait

            if quitting and time.time() > when:
                LOG.debug('quitting')
                break

    def setup_tty(self):
        if os.isatty(sys.stdin.fileno()):
            LOG.debug('putting tty into raw mode')
            self.old_settings = termios.tcgetattr(sys.stdin)
            tty.setraw(sys.stdin)

    def restore_tty(self):
        if os.isatty(sys.stdin.fileno()):
            LOG.debug('restoring tty configuration')
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN,
                              self.old_settings)

    def handle_stdin(self, event):
        if event in (select.POLLHUP, select.POLLNVAL):
            LOG.debug('event %d on stdin', event)

            LOG.debug('eof on stdin')
            self.poll.unregister(sys.stdin)
            self.quit = True

        data = os.read(sys.stdin.fileno(), 1024)

        if not data:
            return

        if self.start_of_line and data == self.escape:
            self.read_escape = True
            return

        if self.read_escape and data == '.':
            LOG.debug('exit by local escape code')
            raise exceptions.UserExit()
        elif self.read_escape:
            self.read_escape = False
            self.send(self.escape)

        self.send(data)

        if data == '\r':
            self.start_of_line = True
        else:
            self.start_of_line = False

    def handle_socket(self, event):
        if event in (select.POLLHUP, select.POLLNVAL):
            self.poll.unregister(self.fileno())
            self.quit = True

        data = self.recv()
        if not data:
            self.poll.unregister(self.fileno())
            self.quit = True
            return

        sys.stdout.write(data)
        sys.stdout.flush()

    def handle_resize(self):
        """send the POST to resize the tty session size in container.

        Resize the container's PTY.
        If `size` is not None, it must be a tuple of (height,width), otherwise
        it will be determined by the size of the current TTY.
        """
        size = self.tty_size(sys.stdout)

        if size is not None:
            rows, cols = size
            try:
                self.tty_resize(height=rows, width=cols)
            except IOError:  # Container already exited
                pass
            except acexceptions.BadRequest:
                pass

    def tty_size(self, fd):
        """Get the tty size

        Return a tuple (rows,cols) representing the size of the TTY `fd`.

        The provided file descriptor should be the stdout stream of the TTY.

        If the TTY size cannot be determined, returns None.
        """

        if not os.isatty(fd.fileno()):
            return None

        try:
            dims = struct.unpack('hh', fcntl.ioctl(fd,
                                                   termios.TIOCGWINSZ,
                                                   'hhhh'))
        except Exception:
            try:
                dims = (os.environ['LINES'], os.environ['COLUMNS'])
            except Exception:
                return None

        return dims


class WebSocketClient(BaseClient):

    def __init__(self, zunclient, url, id, escape='~',
                 close_wait=0.5):
        super(WebSocketClient, self).__init__(
            zunclient, url, id, escape, close_wait)

    def connect(self):
        url = self.url
        LOG.debug('connecting to: %s', url)
        try:
            self.ws = websocket.create_connection(
                url, skip_utf8_validation=True,
                origin=self._compute_origin_header(url),
                subprotocols=["binary", "base64"])
            print('connected to %s, press Enter to continue' % self.id)
            print('type %s. to disconnect' % self.escape)
        except socket.error as e:
            raise exceptions.ConnectionFailed(e)
        except websocket.WebSocketConnectionClosedException as e:
            raise exceptions.ConnectionFailed(e)
        except websocket.WebSocketBadStatusException as e:
            raise exceptions.ConnectionFailed(e)

    def _compute_origin_header(self, url):
        origin = urlparse.urlparse(url)
        if origin.scheme == 'wss':
            return "https://%s:%s" % (origin.hostname, origin.port)
        else:
            return "http://%s:%s" % (origin.hostname, origin.port)

    def fileno(self):
        return self.ws.fileno()

    def send(self, data):
        self.ws.send(data)

    def recv(self):
        return self.ws.recv()


class AttachClient(WebSocketClient):

    def tty_resize(self, height, width):
        """Resize the tty session

        Get the client and send the tty size data to zun api server
        The environment variables need to get when implement sending
        operation.
        """
        height = str(height)
        width = str(width)

        self.cs.containers.resize(self.id, width, height)


class ExecClient(WebSocketClient):

    def __init__(self, zunclient, url, exec_id, id, escape='~',
                 close_wait=0.5):
        super(ExecClient, self).__init__(zunclient, url, id, escape,
                                         close_wait)
        self.exec_id = exec_id

    def tty_resize(self, height, width):
        """Resize the tty session

        Get the client and send the tty size data to zun api server
        The environment variables need to get when implement sending
        operation.
        """
        height = str(height)
        width = str(width)

        self.cs.containers.execute_resize(self.id, self.exec_id, width, height)


class WINCHHandler(object):
    """WINCH Signal handler

    WINCH Signal handler to keep the PTY correctly sized.
    """

    def __init__(self, client):
        """Initialize a new WINCH handler for the given PTY.

        Initializing a handler has no immediate side-effects. The `start()`
        method must be invoked for the signals to be trapped.
        """

        self.client = client
        self.original_handler = None

    def __enter__(self):
        """Enter

        Invoked on entering a `with` block.
        """

        self.start()
        return self

    def __exit__(self, *_):
        """Exit

        Invoked on exiting a `with` block.
        """

        self.stop()

    def start(self):
        """Start

        Start trapping WINCH signals and resizing the PTY.
        This method saves the previous WINCH handler so it can be restored on
        `stop()`.
        """

        def handle(signum, frame):
            if signum == signal.SIGWINCH:
                LOG.debug("Send command to resize the tty session")
                self.client.handle_resize()

        self.original_handler = signal.signal(signal.SIGWINCH, handle)

    def stop(self):
        """stop

        Stop trapping WINCH signals and restore the previous WINCH handler.
        """

        if self.original_handler is not None:
            signal.signal(signal.SIGWINCH, self.original_handler)


def do_attach(zunclient, url, container_id, escape, close_wait):
    if url.startswith("ws://") or url.startswith("wss://"):
        try:
            wscls = AttachClient(zunclient=zunclient, url=url,
                                 id=container_id, escape=escape,
                                 close_wait=close_wait)
            wscls.connect()
            wscls.handle_resize()
            wscls.start_loop()
        except exceptions.ContainerWebSocketException as e:
            print("%(e)s:%(container)s" %
                  {'e': e, 'container': container_id})
    else:
        raise exceptions.InvalidWebSocketLink(container_id)


def do_exec(zunclient, url, container_id, exec_id, escape, close_wait):
    if url.startswith("ws://") or url.startswith("wss://"):
        try:
            wscls = ExecClient(zunclient=zunclient, url=url,
                               exec_id=exec_id,
                               id=container_id, escape=escape,
                               close_wait=close_wait)
            wscls.connect()
            wscls.handle_resize()
            wscls.start_loop()
        except exceptions.ContainerWebSocketException as e:
            print("%(e)s:%(container)s" %
                  {'e': e, 'container': container_id})
    else:
        raise exceptions.InvalidWebSocketLink(container_id)
