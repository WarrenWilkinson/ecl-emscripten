;; -*- Mode: Lisp; Syntax: Common-Lisp -*-
;; $Id$

;; This file is based on SBCL's SB-BSD-SOCKET module and has been
;; heavily modified to work with ECL by Julian Stecklina.
;; Port to Windows Sockets contributed by M. Goffioul.

;; You may do whatever you want with this file. (PUBLIC DOMAIN)

;; Trivial stuff is copied from SBCL's SB-BSD-SOCKETS, which is also
;; in the public domain.

(defpackage "SB-BSD-SOCKETS"
  (:use "CL" "FFI" "SI")
  (:export "GET-HOST-BY-NAME" "GET-HOST-BY-ADDRESS"
	   "SOCKET-BIND" "SOCKET-ACCEPT" "SOCKET-CONNECT"
	   "SOCKET-PEERNAME" "SOCKET-NAME" "SOCKET-LISTEN"
	   "SOCKET-RECEIVE" "SOCKET-CLOSE" "SOCKET-MAKE-STREAM"
	   "GET-PROTOCOL-BY-NAME" "MAKE-INET-ADDRESS" "LOCAL-SOCKET"
	   "SOCKET" "INET-SOCKET" "SOCKET-FILE-DESCRIPTOR" #+:win32 "NAMED-PIPE-SOCKET"
	   "SOCKET-FAMILY" "SOCKET-PROTOCOL" "SOCKET-TYPE"
	   "SOCKET-ERROR" "NAME-SERVICE-ERROR" "NON-BLOCKING-MODE"
	   "HOST-ENT-NAME" "HOST-ENT-ALIASES" "HOST-ENT-ADDRESS-TYPE"
	   "HOST-ENT-ADDRESSES" "HOST-ENT" "HOST-ENT-ADDRESS"))
(in-package "SB-BSD-SOCKETS")

;; Obviously this requires the one or other form of BSD compatible
;; socket interface.

;; Include the neccessary headers
#-:win32
(clines
 "#include <sys/types.h>"
 "#include <sys/socket.h>"
 "#include <sys/un.h>"
 "#include <netdb.h>"
 "#include <strings.h>"
 "#include <netinet/in.h>"
 "#include <errno.h>"
 "#include <fcntl.h>"
 "#include <stdio.h>")
#+:win32
(clines
 "#include <winsock2.h>"
 "typedef unsigned int uint32_t;"
 "typedef int ssize_t, socklen_t;"
 "#define MSG_WAITALL 0"
 "#include <errno.h>"
 "#include <fcntl.h>"
 "#include <stdio.h>")

#+:win32
(progn
  (defvar +wsock-initialized+ nil)
  (defun wsock-initialize ()
    (unless +wsock-initialized+
      (if (c-inline () () :object
        "
{
	WSADATA wsadata;
	if (WSAStartup(MAKEWORD(2,2), &wsadata) == NO_ERROR)
		@(return) = Ct;
	else
		@(return) = Cnil;
}")
        (setf +wsock-initialized+ t)
	(error "Unable to initialize Windows Socket library"))))
  (wsock-initialize)
); #+:win32

(eval-when (:compile-toplevel :load-toplevel)
  (defmacro define-c-constants (&rest args)
    `(progn
       ,@(loop
	    for (lisp-name c-name) on args by #'cddr
	    collect `(defconstant ,lisp-name (c-inline () () :int ,c-name :one-liner t)))))
  (defmacro c-constant (name)
    `(c-inline () () :int ,name :one-liner t)))

#+:win32
(Clines
 "#define AF_LOCAL -1"
)

(define-c-constants
  +af-inet+ "AF_INET"
  +af-local+ "AF_LOCAL")

#+:win32
(defconstant +af-named-pipe+ -2)

;; Foreign functions

(defentry ff-socket (:int :int :int) (:int "socket"))
(defentry ff-listen (:int :int) (:int "listen"))
(defentry ff-close (:int) (:int "close"))
#+:win32 (defentry ff-closesocket (:int) (:int "closesocket"))

;;; This courtesy of Pierre Mai in comp.lang.lisp 08 Jan 1999 00:51:44 +0100
;;; Message-ID: <87lnjebq0f.fsf@orion.dent.isdn.cs.tu-berlin.de>

(defun split (string &optional max (ws '(#\Space #\Tab)))
  "Split `string' along whitespace as defined by the sequence `ws'.
The whitespace is elided from the result.  The whole string will be
split, unless `max' is a non-negative integer, in which case the
string will be split into `max' tokens at most, the last one
containing the whole rest of the given `string', if any."
  (flet ((is-ws (char) (find char ws)))
    (loop for start = (position-if-not #'is-ws string)
          then (position-if-not #'is-ws string :start index)
          for index = (and start
                           (if (and max (= (1+ word-count) max))
                               nil
                             (position-if #'is-ws string :start start)))
          while start
          collect (subseq string start index)
          count 1 into word-count
          while index)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; NAME RESOLVING
;;;

(defclass host-ent ()
  ((name :initarg :name :accessor host-ent-name)
   (aliases :initarg :aliases :accessor host-ent-aliases)
   (address-type :initarg :type :accessor host-ent-address-type)
					; presently always AF_INET
   (addresses :initarg :addresses :accessor host-ent-addresses))
  (:documentation ""))

(defgeneric host-ent-address (host-ent)
  (:documentation ""))

(defmethod host-ent-address ((host-ent host-ent))
  (car (host-ent-addresses host-ent)))

;; FIXME: Do we need to free the hostent structures?
(defun get-host-by-name (host-name)
  "Returns a HOST-ENT instance for HOST-NAME or throws some kind of condition.
HOST-NAME may also be an IP address in dotted quad notation or some other
weird stuff - see gethostbyname(3) for grisly details."
  (let ((host-ent (make-instance 'host-ent)))
    (if (c-inline (host-name host-ent
			     #'(setf host-ent-name)
			     #'(setf host-ent-aliases)
			     #'(setf host-ent-address-type)
			     #'(setf host-ent-addresses))
		  (:cstring t t t t t) t
		  "
{
	struct hostent *hostent = gethostbyname(#0);

	if (hostent != NULL) {
 	        char **aliases;
                char **addrs;
                cl_object aliases_list = Cnil;
                cl_object addr_list = Cnil;
                int length = hostent->h_length;

		funcall(3,#2,make_simple_string(hostent->h_name),#1);
                funcall(3,#4,make_integer(hostent->h_addrtype),#1);

                for (aliases = hostent->h_aliases; *aliases != NULL; aliases++) {
                        aliases_list = CONS(make_simple_string(*aliases),aliases_list);
                }
                funcall(3,#3,aliases_list,#1);

                for (addrs = hostent->h_addr_list; *addrs != NULL; addrs++) {
                        int pos;
                        cl_object vector = funcall(2,@make-array,MAKE_FIXNUM(length));
                        for (pos = 0; pos < length; pos++)
                                aset(vector, pos, MAKE_FIXNUM((unsigned char)((*addrs)[pos])));
                        addr_list = CONS(vector, addr_list);


                }
                funcall(3,#5,addr_list,#1);

                @(return) = #1;
	} else {
		@(return) = Cnil;
	}
}"
		  :side-effects t)
	host-ent
	(name-service-error "get-host-by-name"))))

(defun get-host-by-address (address)
  (assert (typep address 'vector)
	  (and (= (length address) 4)))
  (let ((host-ent (make-instance 'host-ent)))
    (if
     (c-inline (address host-ent
			#'(setf host-ent-name)
			#'(setf host-ent-aliases)
			#'(setf host-ent-address-type)
			#'(setf host-ent-addresses))
	       (t t t t t t) t
	       "
{
        unsigned char vector[4] = { fixint(aref(#0,0)),
                                    fixint(aref(#0,1)),
                                    fixint(aref(#0,2)),
                                    fixint(aref(#0,3)) };
	struct hostent *hostent = gethostbyaddr(vector,4,AF_INET);

	if (hostent != NULL) {
 	        char **aliases;
                char **addrs;
                cl_object aliases_list = Cnil;
                cl_object addr_list = Cnil;
                int length = hostent->h_length;

		funcall(3,#2,make_simple_string(hostent->h_name),#1);
                funcall(3,#4,make_integer(hostent->h_addrtype),#1);

                for (aliases = hostent->h_aliases; *aliases != NULL; aliases++) {
                        aliases_list = CONS(make_simple_string(*aliases),aliases_list);
                }
                funcall(3,#3,aliases_list,#1);

                for (addrs = hostent->h_addr_list; *addrs != NULL; addrs++) {
                        int pos;
                        cl_object vector = funcall(2,@make-array,MAKE_FIXNUM(length));
                        for (pos = 0; pos < length; pos++)
                                aset(vector, pos, MAKE_FIXNUM((unsigned char)((*addrs)[pos])));
                        addr_list = CONS(vector, addr_list);


                }
                funcall(3,#5,addr_list,#1);

                @(return) = #1;
	} else {
		@(return) = Cnil;
	}
}"
	       :side-effects t)
     host-ent
     (name-service-error "get-host-by-address"))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; SOCKET BASE CLASS AND GENERIC FUNCTIONS
;;;

(defclass socket ()
  ((file-descriptor :initarg :descriptor
		    :reader socket-file-descriptor)
   (family :initform (error "No socket family")
	   :reader socket-family)
   (protocol :initarg :protocol
	     :reader socket-protocol
	     :documentation "Protocol used by the socket. If a
keyword, the symbol-name of the keyword will be passed to
GET-PROTOCOL-BY-NAME downcased, and the returned value used as
protocol. Other values are used as-is.")
   (type  :initarg :type
	  :reader socket-type
	  :initform :stream
	  :documentation "Type of the socket: :STREAM or :DATAGRAM.")
   (stream)
   #+:win32
   (non-blocking-p :initform nil))
  (:documentation "Common base class of all sockets, not ment to be
directly instantiated."))


(defmethod print-object ((object socket) stream)
  (print-unreadable-object (object stream :type t :identity t)
                           (princ "descriptor " stream)
                           (princ (slot-value object 'file-descriptor) stream)))

(defmethod shared-initialize :after ((socket socket) slot-names
				     &key protocol type
				     &allow-other-keys)
  (let* ((proto-num
	  (cond ((and protocol (keywordp protocol))
		 (get-protocol-by-name (string-downcase (symbol-name protocol))))
		(protocol protocol)
		(t 0)))
	 (fd (or (and (slot-boundp socket 'file-descriptor)
		      (socket-file-descriptor socket))
		 #+:win32
		 (and (member (socket-family socket) (list +af-named-pipe+ +af-local+)) 0)
		 (ff-socket (socket-family socket)
			    (ecase (or type
				       (socket-type socket))
			      ((:datagram) (c-constant "SOCK_DGRAM"))
			      ((:stream) (c-constant "SOCK_STREAM")))
			    proto-num))))
    (if (= fd -1) (socket-error "socket"))
    (setf (slot-value socket 'file-descriptor) fd
	  (slot-value socket 'protocol) proto-num)
    #+ ignore
    (sb-ext:finalize socket (lambda () (sockint::close fd)))))

;; Generics

(defgeneric socket-bind (socket &rest address)
  (:documentation "Bind SOCKET to ADDRESS, which may vary according to
socket family.  For the INET family, pass ADDRESS and PORT as two
arguments; for FILE address family sockets, pass the filename string.
See also bind(2)"))

(defgeneric socket-accept (socket)
  (:documentation "Perform the accept(2) call, returning a
newly-created connected socket and the peer address as multiple
values"))

(defgeneric socket-connect (socket &rest address)
  (:documentation "Perform the connect(2) call to connect SOCKET to a
  remote PEER.  No useful return value."))

(defgeneric socket-peername (socket)
  (:documentation "Return the socket's peer; depending on the address
  family this may return multiple values"))

(defgeneric socket-name (socket)
  (:documentation "Return the address (as vector of bytes) and port
  that the socket is bound to, as multiple values."))

(defgeneric socket-listen (socket backlog)
  (:documentation "Mark SOCKET as willing to accept incoming connections.  BACKLOG
defines the maximum length that the queue of pending connections may
grow to before new connection attempts are refused.  See also listen(2)"))

(defgeneric socket-receive (socket buffer length
			    &key
			    oob peek waitall element-type)
  (:documentation "Read LENGTH octets from SOCKET into BUFFER (or a freshly-consed buffer if
NIL), using recvfrom(2).  If LENGTH is NIL, the length of BUFFER is
used, so at least one of these two arguments must be non-NIL.  If
BUFFER is supplied, it had better be of an element type one octet wide.
Returns the buffer, its length, and the address of the peer
that sent it, as multiple values.  On datagram sockets, sets MSG_TRUNC
so that the actual packet length is returned even if the buffer was too
small"))

(defgeneric socket-close (socket)
  (:documentation "Close SOCKET.  May throw any kind of error that write(2) would have
thrown.  If SOCKET-MAKE-STREAM has been called, calls CLOSE on that
stream instead"))

(defgeneric socket-make-stream (socket  &rest args)
    (:documentation "Find or create a STREAM that can be used for IO
on SOCKET (which must be connected).  ARGS are passed onto
SB-SYS:MAKE-FD-STREAM."))

(defgeneric non-blocking-mode (socket)
  (:documentation "Is SOCKET in non-blocking mode?"))

(defgeneric (setf non-blocking-mode) (non-blocking-p socket)
  (:documentation "Put SOCKET in non-blocking mode - or not, according to NON-BLOCKING-P"))

(defgeneric socket-close-low-level (socket)
  (:documentation "Close SOCKET at low level. Do not use directly."))

;; Methods

(defmethod socket-listen ((socket socket) backlog)
  (let ((r (ff-listen (socket-file-descriptor socket) backlog)))
    (if (= r -1)
        (socket-error "listen"))))

(defmethod socket-close-low-level ((socket socket))
  (ff-close (socket-file-descriptor socket)))

(defmethod socket-close ((socket socket))
  ;; the close(2) manual page has all kinds of warning about not
  ;; checking the return value of close, on the grounds that an
  ;; earlier write(2) might have returned successfully w/o actually
  ;; writing the stuff to disk.  It then goes on to define the only
  ;; possible error return as EBADF (fd isn't a valid open file
  ;; descriptor).  Presumably this is an oversight and we could also
  ;; get anything that write(2) would have given us.

  ;; note that if you have a socket _and_ a stream on the same fd,
  ;; the socket will avoid doing anything to close the fd in case
  ;; the stream has done it already - if so, it may have been
  ;; reassigned to some other file, and closing it would be bad

  (let ((fd (socket-file-descriptor socket)))
    (unless (eql fd -1) ; already closed
      (cond ((slot-boundp socket 'stream)
	     (close (slot-value socket 'stream)) ;; closes fd indirectly
	     (slot-makunbound socket 'stream))
	    ((= (socket-close-low-level socket) -1)
	     (socket-error "close")))
      (setf (socket-file-descriptor socket) -1))))

;; FIXME: How bad is manipulating fillp directly?
(defmethod socket-receive ((socket socket) buffer length
			   &key oob peek waitall element-type)
  (unless (or buffer length) (error "You have to supply either buffer or length!"))
  (let ((buffer (or buffer (make-array length :element-type element-type)))
	(length (or length (length buffer)))
	(fd (socket-file-descriptor socket)))
    (assert (or (stringp buffer)
		(typep buffer 'vector)))
    (let ((len-recv
	   (c-inline (fd buffer length
		      oob peek waitall)
		     (:int :object :int :bool :bool :bool)
		     :long
		     "
{
        int flags = ( #3 ? MSG_OOB : 0 )  |
                    ( #4 ? MSG_PEEK : 0 ) |
                    ( #5 ? MSG_WAITALL : 0 );
        cl_type type = type_of(#1);

        ssize_t len = recvfrom(#0,( type == t_vector ? #1->vector.self.ch :
                                  ( type == t_string ? #1->string.self : NULL )),
                               #2, flags, NULL,NULL);
        if (len >= 0) {
               if (type == t_vector) { #1->vector.fillp = len; }
               else if (type == t_string) { #1->string.fillp = len; }
        }
        @(return) = len;
}
"
		     :one-liner nil)))
      (if (= len-recv -1)
	  (socket-error "receive")
	  (values buffer len-recv)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; INET SOCKETS
;;;

;; We could refactor a lot here, if we pass sockaddr_foo structs around in Lisp. But
;; I do not feel comfortable with that.

(defun get-protocol-by-name (string-or-symbol)
  "Calls getprotobyname"
  (let ((string (string string-or-symbol)))
    (c-inline (string) (:cstring) :int
	      "getprotobyname(#0)->p_proto"
	      :one-liner t)))

(defun make-inet-address (dotted-quads)
  "Return a vector of octets given a string DOTTED-QUADS in the format
\"127.0.0.1\""
  (map 'vector
       #'parse-integer
       (split dotted-quads nil '(#\.))))

(defclass inet-socket (socket)
  ((family :initform +af-inet+))
  (:documentation "Class representing TCP and UDP sockets.

Examples:

 (make-instance 'inet-socket :type :stream :protocol :tcp)

 (make-instance 'inet-socket :type :datagram :protocol :udp)
"))

(defun make-inet-socket (type protocol)
  "Make an INET socket.  Deprecated in favour of make-instance"
  (make-instance 'inet-socket :type type :protocol protocol))

(Clines
 "
static void fill_inet_sockaddr(struct sockaddr_in *sockaddr, int port,
			       int a1, int a2, int a3, int a4)
{
#if defined(_MSC_VER) || defined(mingw32)
	memset(sockaddr,0,sizeof(struct sockaddr_in));
#else
	bzero(sockaddr,sizeof(struct sockaddr_in));
#endif
	sockaddr->sin_family = AF_INET;
	sockaddr->sin_port = htons(port);
	sockaddr->sin_addr.s_addr= htonl((uint32_t)a1<<24 | (uint32_t)a2<<16 | (uint32_t)a3<<8 | (uint32_t)a4) ;

}
")

(defmethod socket-bind ((socket inet-socket) &rest address)
  (assert (= 2 (length address)) (address) "Socket-bind needs three parameters for inet sockets.")
  (let ((ip (first address))
	(port (second address)))
    (if (= -1
	   (c-inline (port (aref ip 0) (aref ip 1) (aref ip 2) (aref ip 3)
			   (socket-file-descriptor socket))
		     (:int :int :int :int :int :int)
		     :int
		     "
{
	struct sockaddr_in sockaddr;

	fill_inet_sockaddr(&sockaddr, #0, #1, #2, #3, #4);
	@(return) = bind(#5,(struct sockaddr*)&sockaddr, sizeof(struct sockaddr_in));
}"
		     :side-effects t))
	(socket-error "bind"))))

(Clines
"
static cl_object do_accept_inet(cl_object cl_socket_fd)
{
        struct sockaddr_in sockaddr;
        int socket_fd = fixint(cl_socket_fd);
        int addr_len = sizeof(struct sockaddr_in);
        int new_fd = accept(socket_fd, (struct sockaddr*)&sockaddr, &addr_len);

        if (new_fd != -1) {
                uint32_t ip = ntohl(sockaddr.sin_addr.s_addr);
                uint16_t port = ntohs(sockaddr.sin_port);
                cl_object vector = cl_make_array(1,MAKE_FIXNUM(4));

                aset(vector,0, MAKE_FIXNUM( ip>>24 ));
		aset(vector,1, MAKE_FIXNUM( (ip>>16) & 0xFF));
		aset(vector,2, MAKE_FIXNUM( (ip>>8) & 0xFF));
                aset(vector,3, MAKE_FIXNUM( ip & 0xFF ));

		NVALUES = 2;
		VALUES(0) = make_integer(new_fd);
		VALUES(1) = vector;
		return VALUES(0);
	} else return MAKE_FIXNUM(-1);
}
")

(c-inline () () t "cl_def_c_function(@do-accept-inet,do_accept_inet,1)" :one-liner t)

(defmethod socket-accept ((socket inet-socket))
  (multiple-value-bind (fd vector)
      (do-accept-inet (socket-file-descriptor socket))
    (cond
      ((= fd -1)
       (socket-error "accept"))
      (t
       (values
	(make-instance (class-of socket)
		       :type (socket-type socket)
		       :protocol (socket-protocol socket)
		       :descriptor fd)
	vector)))))

(defmethod socket-connect ((socket inet-socket) &rest address)
  (let ((ip (first address))
	(port (second address)))
    (if (= -1
	   (c-inline (port (aref ip 0) (aref ip 1) (aref ip 2) (aref ip 3)
			   (socket-file-descriptor socket))
		     (:int :int :int :int :int :int)
		     :int
		     "
{
	struct sockaddr_in sockaddr;

	fill_inet_sockaddr(&sockaddr, #0, #1, #2, #3, #4);
	@(return) = connect(#5,(struct sockaddr*)&sockaddr, sizeof(struct sockaddr_in));
}"))
	(socket-error "connect"))))

(defmethod socket-peername ((socket inet-socket))
  (let* ((vector (make-array 4))
	 (fd (socket-file-descriptor socket))
	 (port (c-inline (fd vector) (:int t) :int
"{
        struct sockaddr_in name;
        socklen_t len = sizeof(struct sockaddr_in);
        int ret = getpeername(#0,(struct sockaddr*)&name,&len);

        if (ret == 0) {
                uint32_t ip = ntohl(name.sin_addr.s_addr);
                uint16_t port = ntohs(name.sin_port);

                aset(#1,0, MAKE_FIXNUM( ip>>24 ));
		aset(#1,1, MAKE_FIXNUM( (ip>>16) & 0xFF));
		aset(#1,2, MAKE_FIXNUM( (ip>>8) & 0xFF));
                aset(#1,3, MAKE_FIXNUM( ip & 0xFF ));

                @(return) = port;
         } else {
                @(return) = -1;
         }
}")))
    (if (>= port 0)
	(values vector port)
	(socket-error "getpeername"))))

#+:win32
(defmethod socket-close-low-level ((socket inet-socket))
  (ff-closesocket (socket-file-descriptor socket)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; UNIX SOCKETS
;;;

#-:win32
(progn

(defclass local-socket (socket)
  ((family :initform +af-local+))
  (:documentation "Class representing local domain (AF_LOCAL) sockets,
also known as unix-domain sockets."))


(defmethod socket-bind ((socket local-socket) &rest address)
  (assert (= 1 (length address)) (address) "Socket-bind needs two parameters for local sockets.")
  (let ((name (first address))
	(fd (socket-file-descriptor socket))
	(family (socket-family socket)))
    (if (= -1
	   (c-inline (fd name family) (:int :cstring :int) :int
		     "
{
        struct sockaddr_un sockaddr;
	size_t size;

#ifdef BSD
        sockaddr.sun_len = sizeof(struct sockaddr_un);
#endif
        sockaddr.sun_family = #2;
        strncpy(&sockaddr.sun_path,#1,sizeof(sockaddr.sun_path));
	sockaddr.sun_path[sizeof(sockaddr.sun_path)-1] = '\0';

        @(return) = bind(#0,&sockaddr, sizeof(struct sockaddr_un));
}"))
	(socket-error "bind"))))

(Clines
 "
static cl_object do_accept_un(cl_object cl_socket_fd)
{
        struct sockaddr_un sockaddr;
        int socket_fd = fixint(cl_socket_fd);
        int addr_len = sizeof(struct sockaddr_un);
        int new_fd = accept(socket_fd, &sockaddr, &addr_len);

        NVALUES = 2;
        VALUES(0) = make_integer(new_fd);
	VALUES(1) = (new_fd == -1) ? Cnil : make_string_copy(&sockaddr.sun_path);
        return VALUES(0);
}
")

(c-inline () () nil  "cl_def_c_function(@do-accept-un,do_accept_un,1)" :one-liner t)

(defmethod socket-accept ((socket local-socket))
  (multiple-value-bind (fd name)
      (do-accept-un (socket-file-descriptor socket))
    (cond
      ((= fd -1)
       (socket-error "accept"))
      (t
       (values
	(make-instance (class-of socket)
		       :type (socket-type socket)
		       :protocol (socket-protocol socket)
		       :descriptor fd)
	name)))))

(defmethod socket-connect ((socket local-socket) &rest address)
  (assert (= 1 (length address)) (address) "Socket-connect needs two parameters for local sockets.")
  (let ((path (first address))
	(fd (socket-file-descriptor socket))
	(family (socket-family socket)))
    (if (= -1
	   (c-inline (fd family path) (:int :int :cstring) :int
		     "
{
        struct sockaddr_un sockaddr;

#ifdef BSD
        sockaddr.sun_len = sizeof(struct sockaddr_un);
#endif
        sockaddr.sun_family = #1;
        strncpy(&sockaddr.sun_path,#2,sizeof(sockaddr.sun_path));
	sockaddr.sun_path[sizeof(sockaddr.sun_path)-1] = '\0';

        @(return) = connect(#0,&sockaddr, sizeof(struct sockaddr_un));
}"))
	(socket-error "connect"))))

(defmethod socket-peername ((socket local-socket))
  (let* ((fd (socket-file-descriptor socket))
	 (peer (c-inline (fd) (:int) t
			 "
{
        struct sockaddr_un name;
        socklen_t len = sizeof(struct sockaddr_un);
        int ret = getpeername(#0,&name,&len);

        if (ret == 0) {
                @(return) = make_string_copy(&name.sun_path);
        } else {
                @(return) = Cnil;
        }
}")))
    (if peer
	peer
	(socket-error "getpeername"))))

) ;#-:win32


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; UNIX SOCKETS [WIN32, using the cygwin way]
;;;

#+:win32
(progn

(defclass local-socket (socket)
  ((family :initform +af-local+)
   proxy-socket local-path)
  (:documentation "Class representing local domain (AF_LOCAL) sockets,
also known as unix-domain sockets."))

(defmethod initialize-instance :after ((socket local-socket) &rest args)
  (declare (ignore args))
  (with-slots (protocol type) socket
    (setf (slot-value socket 'proxy-socket)
          (make-instance 'inet-socket :protocol protocol :type type))))

(defmethod socket-bind ((socket local-socket) &rest address)
  (assert (= 1 (length address)) (address) "Socket-bind needs two parameters for local sockets.")
  (with-slots (proxy-socket local-path) socket
    (socket-bind proxy-socket #(127 0 0 1) 0)
    (multiple-value-bind (ip port) (socket-peername proxy-socket)
      (handler-case 
        (with-open-file (fd (first address) :if-exists :error :if-does-not-exist :create :direction :output)
	  (format fd "!<socket >~D 00000000-00000000-00000000-00000000" port))
	(file-error ()
	  (socket-close proxy-socket)
	  (c-inline () () nil "WSASetLastError(WSAEADDRINUSE)" :one-liner t)
	  (socket-error "socket-bind")))
      (setf local-path (first address))
      socket)))

(defmethod socket-accept ((socket local-socket))
  (multiple-value-bind (new-socket addr) (socket-accept (slot-value socket 'proxy-socket))
    (values socket (slot-value socket 'local-path))))

(defmethod socket-connect ((socket local-socket) &rest address)
  (assert (= 1 (length address)) (address) "Socket-connect needs two parameters for local sockets.")
  (with-slots (proxy-socket local-path) socket
    (handler-case
      (with-open-file (fd (first address) :if-does-not-exist :error :direction :input)
        (let ((buf (make-string 128)) port)
	  (read-sequence buf fd)
	  (unless (and (string-equal "!<socket >" (subseq buf 0 10))
	               (typep (setq port (read-from-string (subseq buf 10) nil 'eof)) '(integer 0 65535)))
	    (c-inline () () nil "WSASetLastError(WSAEFAULT)" :one-liner t)
	    (socket-error "connect"))
	  (prog1
	    (socket-connect proxy-socket #(127 0 0 1) port)
	    (setf local-path (first address)))))
      (file-error ()
        (socket-error "connect")))))

(defmethod socket-peername ((socket local-socket))
  (unless (slot-boundp socket 'local-path)
    (c-inline () () nil "WSASetLastError(WSAENOTCONN)" :one-liner t)
    (socket-error "socket-peername"))
  (slot-value socket 'local-path))

(defmethod socket-close ((socket local-socket))
  (socket-close (slot-value socket 'proxy-socket))
  (slot-makunbound socket 'local-path))

(defmethod socket-make-stream ((socket local-socket) &rest args)
  (apply #'socket-make-stream (cons (slot-value socket 'proxy-socket) args)))

(defmethod non-blocking-mode ((socket local-socket))
  (non-blocking-mode (slot-value socket 'proxy-socket)))

(defmethod (setf non-blocking-mode) (non-blocking-p (socket local-socket))
  (setf (non-blocking-mode (slot-value socket 'proxy-socket)) non-blocking-p))

) ;#+:win32

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; NAMED PIPE SOCKETS [WIN32]
;;;

#+:win32
(progn

(defclass named-pipe-socket (socket)
  ((family :initform +af-named-pipe+)
   (pipe-name :initarg :pipe-name))
  (:documentation "Class representing Win32 named pipe, using a socket-like interface."))

(defmethod socket-bind ((socket named-pipe-socket) &rest address)
  (assert (= 1 (length address)) (address) "Socket-bind needs two parameters for local sockets.")
  (let* ((pipe-name (concatenate 'string "\\\\.\\pipe\\" (first address)))
         (hnd (c-inline (pipe-name) (:cstring) :int
	                "
{
	HANDLE hnd = CreateNamedPipe(
			#0,
			PIPE_ACCESS_DUPLEX,
			PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
			PIPE_UNLIMITED_INSTANCES,
			4096,
			4096,
			NMPWAIT_USE_DEFAULT_WAIT,
			NULL);
	if (hnd == INVALID_HANDLE_VALUE)
		@(return) = -1;
	else
		@(return) = _open_osfhandle(hnd, O_RDWR);
}")))
    (when (= hnd -1)
      (socket-error "CreateNamedPipe"))
    (setf (slot-value socket 'pipe-name) pipe-name)
    (setf (slot-value socket 'file-descriptor) hnd)))

(defmethod socket-accept ((socket named-pipe-socket))
  (let* ((fd (socket-file-descriptor socket))
         (afd (c-inline (fd) (:int) :int
	                "
{
	HANDLE hnd = _get_osfhandle(#0), dupHnd;
	if (ConnectNamedPipe(hnd, NULL) != 0 || GetLastError() == ERROR_PIPE_CONNECTED) {
		@(return) = #0;
	} else
		@(return) = -1;
}"
                        :one-liner nil)))
    (cond
      ((= afd -1)
       (socket-error "accept"))
      (t
       ;; rebind the socket to create a new named pipe instance in the server
       (socket-bind socket (subseq (slot-value socket 'pipe-name) 9))
       (values
	(make-instance (class-of socket)
		       :type (socket-type socket)
		       :protocol (socket-protocol socket)
		       :descriptor afd
		       :pipe-name (slot-value socket 'pipe-name))
	(slot-value socket 'pipe-name))))))

(defmethod socket-connect ((socket named-pipe-socket) &rest address)
  (assert (= 1 (length address)) (address) "Socket-connect needs two parameters for local sockets.")
  (let* ((path (first address))
	 (pipe-name (concatenate 'string "\\\\.\\pipe\\" path)))
    (if (= -1
	   (setf (slot-value socket 'file-descriptor)
	         (c-inline (pipe-name) (:cstring) :int
		     "
{
	HANDLE hnd = CreateFile(
			#0,
			GENERIC_READ | GENERIC_WRITE,
			0,
			NULL,
			OPEN_EXISTING,
			0,
			NULL);
	if (hnd == INVALID_HANDLE_VALUE)
		@(return) = -1;
	else
		@(return) = _open_osfhandle(hnd, O_RDWR);
}")))
	(socket-error "connect")
	(setf (slot-value socket 'pipe-name) pipe-name))))

(defmethod socket-peername ((socket named-pipe-socket))
  (slot-value socket 'pipe-name))

(defmethod (setf non-blocking-mode) (non-blocking-p (socket named-pipe-socket))
  (let ((fd (socket-file-descriptor socket)))
    (if (= 0
           (c-inline (fd non-blocking-p) (:int t) :int
                     "
{
	DWORD mode = PIPE_READMODE_BYTE | (#1 == Ct ? PIPE_NOWAIT : PIPE_WAIT);
	@(return) = SetNamedPipeHandleState(_get_osfhandle(#0), &mode, NULL, NULL);
}"
                     :one-liner nil))
      (socket-error "SetNamedPipeHandleState")
      (setf (slot-value socket 'non-blocking-p) non-blocking-p))))

(defmethod socket-close ((socket named-pipe-socket))
  (let ((fd (socket-file-descriptor socket)))
    (unless (c-inline (fd) (:int) t
                  "
{
	DWORD flags;
	if (!GetNamedPipeInfo(_get_osfhandle(#0), &flags, NULL, NULL, NULL))
		@(return) = Cnil;
	if (flags == PIPE_CLIENT_END || DisconnectNamedPipe(_get_osfhandle(#0)))
		@(return) = Ct;
	else
		@(return) = Cnil;
}"
                  :one-liner nil)
      (socket-error "DisconnectNamedPipe"))
    (call-next-method)))

) ;#+:win32

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; NON-BLOCKING MODE
;;;

(defmethod non-blocking-mode ((socket socket))
  #-:win32
  (let ((fd (socket-file-descriptor socket)))
    (not (zerop (c-inline (fd) (:int) :int "fcntl(#0,F_GETFL,NULL)&O_NONBLOCK" :one-liner t))))
  #+:win32
  (slot-value socket 'non-blocking-p)
)

(defmethod (setf non-blocking-mode) (non-blocking-p (socket socket))
  (let ((fd (socket-file-descriptor socket))
	(nblock (if non-blocking-p 1 0)))
    (if (= -1 (c-inline (fd nblock) (:int :int) :int
	      #+:win32
	      "
{
	int blocking_flag = (#1 ? 1 : 0);
	@(return) = ioctlsocket(#0, FIONBIO, (u_long*)&blocking_flag);
}"
	      #-:win32
	      "
{
        int oldflags = fcntl(#0,F_GETFL,NULL);
        int newflags = (oldflags & ~O_NONBLOCK) |
                       (#1 ? O_NONBLOCK : 0);
        @(return) = fcntl(#0,F_SETFL,newflags);
}"))
	(socket-error #-:win32 "fcntl" #+:win32 "ioctlsocket")
	#-:win32 non-blocking-p
	#+:win32 (setf (slot-value socket 'non-blocking-p) non-blocking-p))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; STREAMS
;;;
;;; To actually read/write to/from the sockets, we use Lisp streams. The
;;; following functions take care of building the streams. Fortunately
;;; we do not have to care about things like buffering, binary streams,
;;; etc, but we rather reuse the code from the C core. (For instance
;;; the sockets will be closed upon garbage collection)
;;;

(defun make-stream-from-fd (fd mode &optional (name "FD-STREAM"))
  (assert (stringp name) (name) "name must be a string.")
  (c-inline (name fd (ecase mode
		       (:input (c-constant "smm_input"))
		       (:output (c-constant "smm_output"))
		       (:input-output (c-constant "smm_io"))
		       #+:win32
		       (:input-wsock (c-constant "smm_input_wsock"))
		       #+:win32
		       (:output-wsock (c-constant "smm_output_wsock"))
		       #+:win32
		       (:input-output-wsock (c-constant "smm_io_wsock"))
		       ))
	    (t :int :int)
	    t
	    "ecl_make_stream_from_fd(#0,#1,#2)"
	    :one-liner t))

(defgeneric socket-make-stream (socket  &rest args)
    (:documentation "Find or create a STREAM that can be used for IO
on SOCKET (which must be connected).  ARGS are ignored."))

(defmethod socket-make-stream ((socket socket)  &rest args)
  (declare (ignore args))
  (let ((stream (and (slot-boundp socket 'stream)
		     (slot-value socket 'stream))))
    (unless stream
      (setf stream (let ((fd (socket-file-descriptor socket)))
		     (make-stream-from-fd fd #-:win32 :input-output #+:win32 :input-output-wsock)))
      (setf (slot-value socket 'stream) stream)
      #+ ignore
      (sb-ext:cancel-finalization socket))
    stream))

#+:win32
(defmethod socket-make-stream ((socket named-pipe-socket) &rest args)
  (declare (ignore args))
  (let ((stream (and (slot-boundp socket 'stream)
		     (slot-value socket 'stream))))
    (unless stream
      (setf stream (let ((fd (socket-file-descriptor socket)))
		     (c-inline (fd) (:int) t
		               "
{
	cl_object in_strm, out_strm;
	in_strm = ecl_make_stream_from_fd(make_simple_string(\"FD-STREAM\"), #0, smm_input);
	out_strm = ecl_make_stream_from_fd(make_simple_string(\"FD-STREAM\"), #0, smm_output);
	@(return) = make_two_way_stream(in_strm, out_strm);
}"
                               :one-liner nil)))
      (setf (slot-value socket 'stream) stream)
      #+ ignore
      (sb-ext:cancel-finalization socket))
    stream))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; ERROR HANDLING
;;;
;;; A plethora of conditions are defined below, almost one for each
;;; possible error produced by the socket or DNS interface.
;;;

#+:win32
(defun get-win32-error-string (num)
  (c-inline (num) (:int) t
	"{char *lpMsgBuf;
	  cl_object msg;
	  FormatMessage(
	    FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM,
	    NULL,
	    #0,
	    0,
	    (LPTSTR)&lpMsgBuf,
	    0,
	    NULL);
	  msg = make_string_copy(lpMsgBuf);
	  LocalFree(lpMsgBuf);
	  @(return) = msg;}"
	  :one-liner nil))

;;;
;;; 1) SOCKET ERRORS
;;;

(define-condition socket-error (error)
  ((errno :initform nil
          :initarg :errno
          :reader socket-error-errno)
   (symbol :initform nil :initarg :symbol :reader socket-error-symbol)
   (syscall  :initform "outer space" :initarg :syscall :reader socket-error-syscall))
  (:report (lambda (c s)
             (let ((num (socket-error-errno c)))
               (format s "Socket error in \"~A\": ~A (~A)"
                       (socket-error-syscall c)
                       (or (socket-error-symbol c) (socket-error-errno c))
		       #+:win32
		       (get-win32-error-string num)
		       #-:win32
		       (c-inline (num) (:int) :cstring
				 "strerror(#0)" :one-liner t)))))
  (:documentation "Common base class of socket related conditions."))

(defmacro define-socket-condition (symbol name)
  `(progn
     (defconstant ,symbol (c-constant ,(symbol-name symbol)))
     (define-condition ,name (socket-error)
       ((symbol :reader socket-error-symbol :initform (quote ,symbol))))
     (export ',name)
     (push (cons ,symbol (quote ,name)) *conditions-for-errno*)))

(defparameter *conditions-for-errno* nil)
;;; this needs the rest of the list adding to it, really.  They also
;;; need symbols to be added to constants.ccon
;;; I haven't yet thought of a non-kludgey way of keeping all this in
;;; the same place
#+:win32
(Clines
  "#define EADDRINUSE WSAEADDRINUSE"
  "#define ECONNREFUSED WSAECONNREFUSED"
  "#define ETIMEDOUT WSAETIMEDOUT"
  "#define ENOBUFS WSAENOBUFS"
  "#define EOPNOTSUPP WSAEOPNOTSUPP"
  "#define EPROTONOSUPPORT WSAEPROTONOSUPPORT"
  "#define ESOCKTNOSUPPORT WSAESOCKTNOSUPPORT"
  "#define ENETUNREACH WSAENETUNREACH"
  "#define NETDB_INTERNAL WSAEAFNOSUPPORT"
  "#define NETDB_SUCCESS 0"
)
(define-socket-condition EADDRINUSE address-in-use-error)
(define-socket-condition EAGAIN interrupted-error)
(define-socket-condition EBADF bad-file-descriptor-error)
(define-socket-condition ECONNREFUSED connection-refused-error)
(define-socket-condition ETIMEDOUT operation-timeout-error)
(define-socket-condition EINTR interrupted-error)
(define-socket-condition EINVAL invalid-argument-error)
(define-socket-condition ENOBUFS no-buffers-error)
(define-socket-condition ENOMEM out-of-memory-error)
(define-socket-condition EOPNOTSUPP operation-not-supported-error)
(define-socket-condition EPERM operation-not-permitted-error)
(define-socket-condition EPROTONOSUPPORT protocol-not-supported-error)
(define-socket-condition ESOCKTNOSUPPORT socket-type-not-supported-error)
(define-socket-condition ENETUNREACH network-unreachable-error)


(defun condition-for-errno (err)
  (or (cdr (assoc err *conditions-for-errno* :test #'eql)) 'socket-error))

(defun socket-error (where)
  (let* ((errno  (c-constant #-:win32 "errno" #+:win32 "WSAGetLastError()"))
         (condition (condition-for-errno errno)))
    (error condition :errno errno  :syscall where)))

;;;
;;; 2) DNS ERRORS
;;;

(defvar *name-service-errno* 0
  "The value of h_errno, after it's been fetched from Unix-land by calling
GET-NAME-SERVICE-ERRNO")

(defun name-service-error (where)
  (get-name-service-errno)
  ;; Comment next to NETDB_INTERNAL in netdb.h says "See errno.".
  ;; This special case treatment hasn't actually been tested yet.
  (if (= *name-service-errno* (c-constant "NETDB_INTERNAL"))
      (socket-error where)
    (let ((condition
	   (condition-for-name-service-errno *name-service-errno*)))
      (error condition :errno *name-service-errno* :syscall where))))

(define-condition name-service-error (condition)
  ((errno :initform nil
	  :initarg :errno
	  :reader name-service-error-errno)
   (symbol :initform nil :initarg :symbol :reader name-service-error-symbol)
   (syscall :initform "an unknown location" :initarg :syscall :reader name-service-error-syscall))
  (:report (lambda (c s)
	     (let ((num (name-service-error-errno c)))
	       (format s "Name service error in \"~A\": ~A (~A)"
		       (name-service-error-syscall c)
		       (or (name-service-error-symbol c)
			   (name-service-error-errno c))
		       (get-name-service-error-message num))))))

(defmacro define-name-service-condition (symbol name)
  `(progn
     (defconstant ,symbol (c-constant ,(symbol-name symbol)))
     (define-condition ,name (name-service-error)
       ((symbol :reader name-service-error-symbol :initform (quote ,symbol))))
     (push (cons ,symbol (quote ,name)) *conditions-for-name-service-errno*)
     (export (quote ,symbol))))

(defparameter *conditions-for-name-service-errno* nil)

(define-name-service-condition NETDB_INTERNAL netdb-internal-error)
(define-name-service-condition NETDB_SUCCESS netdb-success-error)
(define-name-service-condition HOST_NOT_FOUND host-not-found-error)
(define-name-service-condition TRY_AGAIN try-again-error)
(define-name-service-condition NO_RECOVERY no-recovery-error)
;; this is the same as the next one
;;(define-name-service-condition NO_DATA no-data-error)
(define-name-service-condition NO_ADDRESS no-address-error)

(defun condition-for-name-service-errno (err)
  (or (cdr (assoc err *conditions-for-name-service-errno* :test #'eql))
      'name-service))

(defun get-name-service-errno ()
  (setf *name-service-errno* (c-constant #-:win32 "h_errno" #+:win32 "WSAGetLastError()")))

(defun get-name-service-error-message (num)
  #-:win32
  (c-inline (num) (:int) :cstring "hstrerror(#0)" :one-liner t)
  #+:win32
  (get-win32-error-string num)
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; SOCKET OPTIONS
;;;

(defun get-sockopt-int (fd const)
  (let ((ret (c-inline (fd const) (:int :int) t
"{
        int sockopt;
        socklen_t socklen = sizeof(int);
        int ret = getsockopt(#0,SOL_SOCKET,#1,&sockopt,&socklen);

        @(return) = (ret == 0) ? make_integer(sockopt) : Cnil;
}")))
    (if ret
	ret
	(error "Sockopt error: ~A" (c-inline () () :cstring "strerror(errno)" :one-liner t)))))


(defun get-sockopt-bool (fd const)
  (let ((ret (c-inline (fd const) (:int :int) t
"{
        int sockopt;
        socklen_t socklen = sizeof(int);
        int ret = getsockopt(#0,SOL_SOCKET,#1,&sockopt,&socklen);

        @(return) = (ret == 0) ? Ct : Cnil;
}")))
    (if ret
	ret
	(error "Sockopt error: ~A" (c-inline () () :cstring "strerror(errno)" :one-liner t)))))

(defun set-sockopt-int (fd const value)
  (let ((ret (c-inline (fd const value) (:int :int :int) t
"{
        int sockopt = #2;
        int ret = setsockopt(#0,SOL_SOCKET,#1,&sockopt,sizeof(int));
        @(return) = (ret == 0) ? Ct : Cnil;
}")))
    (if ret
	value
	(error "Sockopt error: ~A" (c-inline () () :cstring "strerror(errno)" :one-liner t)))))

(defun set-sockopt-bool (fd const value)
  (let ((ret (c-inline (fd const value) (:int :int :object) t
"{
        int sockopt = (#2 == Cnil) ? 0 : 1;
        int ret = setsockopt(#0,SOL_SOCKET,#1,&sockopt,sizeof(int));
        @(return) = (ret == 0) ? Ct : Cnil;
}")))
    (if ret
	ret
	(error "Sockopt error: ~A" (c-inline () () :cstring "strerror(errno)" :one-liner t)))))

(eval-when (:compile-toplevel :load-toplevel)
  (defmacro define-sockopt (name c-const type &optional (read-only nil))
    `(progn
       (export ',name)
       (defun ,name (socket)
	 (,(intern (format nil "GET-SOCKOPT-~A" type))
	   (socket-file-descriptor socket)
	   (c-constant ,c-const)))
       ,@(unless read-only
	   `((defun (setf ,name) (value socket)
	       (,(intern (format nil "SET-SOCKOPT-~A" type))
		 (socket-file-descriptor socket)
		 (c-constant ,c-const)
		 value)))))))

(define-sockopt sockopt-type "SO_TYPE" int t)
(define-sockopt sockopt-receive-buffer "SO_RCVBUF" int)
(define-sockopt sockopt-reuse-address "SO_REUSEADDR" bool)
(define-sockopt sockopt-keep-alive "SO_KEEPALIVE" bool)
(define-sockopt socket-dont-route "SO_DONTROUTE" bool)
(define-sockopt socket-linger "SO_LINGER" bool)

#-(or :linux :win32)
(define-sockopt sockopt-reuse-port "SO_REUSEPORT" bool)

;; Add sockopts here as you need them...

;; Finished loading
(provide 'sockets)