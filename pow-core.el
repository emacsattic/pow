;;; pow-core.el --- pow (http://pow.cx/) manager core component

;; Copyright (c) 2013  Free Software Foundation, Inc.

;; Author: yukihiro hara <yukihr@gmail.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

;;; Code:

(eval-when-compile (require 'cl))

;;
;; customs
;;

(defgroup pow nil
  "pow (http://pow.cx/) apps manager"
  :group 'development
  :prefix "pow-")

(defcustom pow-symlink-directory "~/.pow"
  "Directory for symlinks of pow apps."
  :type 'string
  :group 'pow)

(defcustom pow-url-format "http://%s.dev/"
  "Url format of rack application registered on Pow. This is passed to format function with one argument: app-name."
  :type 'string
  :group 'pow)

(defcustom pow-browse-url-function 'browse-url
  "Function to browse app, takes an app-url."
  :type 'function
  :group 'pow)



;;
;; helper
;;

(defun pow-rack-project-root-for-dir (dir)
  "Return the root directory of the rack project within which DIR is found."
  (setq dir (expand-file-name dir))
  (cond ((or (not (file-directory-p dir))
          ;;; regexp to match windows roots, tramp roots, or regular posix roots
          ;;; copied from rinari.el
          (string-match "\\(^[[:alpha:]]:/$\\|^/[^\/]+:/?$\\|^/$\\)" dir))
         nil)
        ((file-exists-p (expand-file-name "config.ru" dir)) dir)
        (t (pow-rack-project-root-for-dir (replace-regexp-in-string "[^/]+/?$" "" dir)))))

(defun pow-same-file-p (&rest paths)
  "Check if all passed paths are pointing to same path."
  (reduce #'(lambda (l r)
              (when (and
                     (stringp l) (stringp r)
                     (equal (file-truename l) (file-truename r)))
                (file-truename r)))
          (mapcar #'(lambda (path)
                      (replace-regexp-in-string "/$" "" path)) paths)
          :start 0))

(defun pow-message (format-string &rest args)
  "Message utility. format-string and rest args are passed to `format',
and then pass the output to `message'."
  (message (apply 'format (concat "Pow: " format-string) args)))

(defun pow-error (format-string &rest args)
  "Error utility. format-string and rest args are passed to `error'."
  (apply 'error (concat "Pow: " format-string) args))

(defun pow-user-error (format-string &rest args)
  "User error utility. format-string and rest args are passed to `user-error'."
  (apply 'user-error (concat "Pow: " format-string) args))

(defun pow-filename-last-directory (path)
  "Return the last entry of path."
  (string-match "\\/\\([^\\/]+\\)\\/?$" path)
  (match-string 1 path))



;;
;; App
;;

;; errors

(put 'pow-app-already-exists 'error-conditions
     '(pow-app-already-exists pow-app-error error))
(put 'pow-app-already-exists 'error-message
     "App already exists")

(put 'pow-app-couldnt-delete 'error-conditions
     '(pow-app-couldnt-delete pow-app-error error))
(put 'pow-app-couldnt-delete 'error-message
     "Couldn't delete app")

(put 'pow-app-couldnt-restart 'error-conditions
     '(pow-app-couldnt-restart pow-app-error error))
(put 'pow-app-couldnt-restart 'error-message
     "Couldn't restart app")

;; struct

(defstruct (pow-app
            (:constructor nil)
            (:constructor pow-app--inner-make))
  "A structure abstructing pow app symlinks."
  (symlink-directory pow-symlink-directory)
  path
  (name "")
  )

(defun make-pow-app (&rest options)
  "Constructor for `pow-app'.

options:
`symlink-directory': symlink-directory of pow apps. (defalut: `pow-symlink-directory')
`path': path to pow app project.
`name': name of the pow app."
  (if (plist-get options :path)
      (setq options (plist-put options :path
                               (expand-file-name
                                (plist-get options :path)))))
  (let ((pow-app
         (apply 'pow-app--inner-make options)))
    (if (not (plist-get options :name))
        (pow-app-set-name-with-path pow-app))
    pow-app))

(defun pow-app-set-name-with-path (app)
  "Set app name to last entry of the `path'."
  (let* ((path (pow-app-path app))
         (name (pow-filename-last-directory path)))
    (setf (pow-app-name app) name)))

(defun pow-app-set-name-default (app)
  "Set app name to \"default\"."
  (setf (pow-app-name app) "default"))

(defun pow-app-url (app)
  "Gertter for url of the pow app."
  (format pow-url-format (pow-app-name app)))

(defun pow-app-open (app)
  "Open pow app url with function referenced by `pow-browse-url-function'."
  (let ((url (pow-app-url app)))
    (funcall pow-browse-url-function url)))

(defun pow-app-symlink-path (app)
  "Gertter for symlink's whole path of the pow app."
  (expand-file-name
   (pow-app-name app)
   (pow-app-symlink-directory app)))

(defun pow-app-save (app)
  "Save pow app as symlink in `symlink-directory'."
  (make-directory (pow-app-symlink-directory app) 'parents)
  (condition-case err
      (make-symbolic-link (pow-app-path app)
                          (pow-app-symlink-path app))
    (file-already-exists
     (signal 'pow-app-already-exists
             (format "App \"%s\" already exists" (pow-app-name app))))))

(defun pow-app-delete (app)
  "Delete pow app symlink in `symlink-directory'."
  (condition-case err
      (delete-file (pow-app-symlink-path app))
    (file-error
     (signal 'pow-app-couldnt-delete
             (format "Couldn't delete app \"%s\". Check if directory \"%s\" is writable"
                     (pow-app-name app)
                     pow-symlink-directory)))))

(defun pow-app-restart (app)
  "Flag pow app to restart on next request."
  (condition-case err
      (let* ((txt "restart.txt")
             (dir (expand-file-name "tmp" (pow-app-path app)))
             (path (expand-file-name txt dir)))
        (make-directory dir 'parents)
        (write-region "" nil path nil 'quiet))
    (file-error
     (signal 'pow-app-couldnt-restart
             (format "Couldn't restart app \"%s\". Check if file \"%s\" is writable"
                     (pow-app-name app)
                     path)))))

(defun pow-app-load-all ()
  "Load all pow apps in `symlink-directory'."
  (let* ((dir pow-symlink-directory)
         (symlinks (directory-files dir)))
    (remove-if
     #'nil
     (mapcar
      #'(lambda (symlink)
          (let ((symlink-path (expand-file-name symlink dir)))
            (when (and (not (equal "." symlink))
                       (not (equal ".." symlink))
                       (file-symlink-p symlink-path))
              (make-pow-app :path (file-chase-links symlink-path)
                            :name symlink)))
                    ) symlinks))))

(defun pow-app-load-for-project (project-dir)
  "Load pow app for `project-dir'."
  (remove-if #'(lambda (app)
                 (not (pow-same-file-p
                       (pow-app-path app) project-dir)))
             (pow-app-load-all)))

(defun pow-app-load-for-dir (dir)
  "Load pow app for `dir'.
This function will find root project directory of `dir'
and pass it to `pow-app-load-for-project'."
  (let ((project-path (pow-rack-project-root-for-dir dir)))
    (when project-path
      (pow-app-load-for-project project-path))))

(defun pow-app-load-by-name (name)
  "Load pow app for `name'."
  (car
   (remove-if #'(lambda (app)
                  (not (equal name (pow-app-name app))))
              (pow-app-load-all))))



;;
;; user function
;;

;; core function

(put 'pow-app-not-found 'error-conditions
     '(pow-app-not-found pow-error error))
(put 'pow-app-not-found 'error-message
     "App not found")

(defun pow-register-app (name path)
  "Register pow app for `name' and `path'."
  (let ((app (make-pow-app :path path :name name)))
    (pow-app-save app)))

(defmacro pow--with-name-or-app (name-or-app app &rest body)
  "An macro receives `name-or-app' arg and call `body' certainly with `app'."
  (declare (indent 2))
  `(let (,app name)
     (if (pow-app-p ,name-or-app)
         (setq ,app ,name-or-app name (pow-app-name ,name-or-app))
       (setq ,app (pow-app-load-by-name ,name-or-app)
             name ,name-or-app))
     (if (null ,app)
         (signal 'pow-app-not-found
                 (format "App \"%s\" not found" name))
       (progn ,@body))))

(defun pow-unregister-app (name-or-app)
  "Unregister app specified by `name-or-app'."
  (pow--with-name-or-app name-or-app app
    (pow-app-delete app)))

(defun pow-open-app (name-or-app)
  "Open app specified by `name-or-app'."
  (pow--with-name-or-app name-or-app app
    (pow-app-open app)))

(defun pow-restart-app (name-or-app)
  "Restart app specified by `name-or-app'."
  (pow--with-name-or-app name-or-app app
    (pow-app-restart app)))


;; interactive function

(defmacro pow-wrap-error-in-message (message-on-success &rest body)
  "A macro translates errors to error message for interactive fns."
  (declare (indent 1))
  `(condition-case err
       (progn
         ,@body
         (unless (null ,message-on-success)
           (pow-message ,message-on-success)))
     (error (pow-error (cdr err)))))

(defmacro pow-with-rack-project-root (root-path &rest body)
  "A macro verifies current-directory is in rack project,
and call `body' with project\'s `root-path'."
  (declare (indent 1))
  `(let ((,root-path (pow-rack-project-root-for-dir default-directory)))
     (if ,root-path
         (progn ,@body)
       (pow-user-error "Not in rack project"))))

;;;###autoload
(defun pow-register-current-app (&optional name)
  "Register current project as an pow app."
  (interactive)
  (pow-with-rack-project-root path
    (let (app
          (appname (pow-filename-last-directory path)))
      (when (null name)
          (setq name (read-string (format "App Name(%s):" appname)
                                  nil nil appname)))
      (pow-wrap-error-in-message
          (format "Registered app \"%s\"" name)
        (pow-register-app name path)))))

;;;###autoload
(defun pow-register-current-app-as-default ()
  "Registers current project as an pow app named \"default\"."
  (interactive)
  (pow-register-current-app "default"))

(defmacro pow-with-current-apps (apps &rest body)
  "Execute `body' with `apps' of current project."
  (declare (indent 1))
  `(let ((,apps (pow-app-load-for-dir default-directory)))
     (if (not (null ,apps))
         (progn ,@body)
       (pow-error "App for current project was not found"))))

(defmacro pow-with-current-app (app &rest body)
  "Execute `body' with an `app' of current project.
If there is many app registered for the current project,
shows prompt to choose one app from the apps."
  (declare (indent 1))
  `(pow-with-current-apps apps
     (if (eq (length apps) 1)
         (let ((,app (car apps)))
           (progn ,@body))
       (let* ((names (mapcar #'(lambda (-app) (pow-app-name -app)) apps))
              (name
               (completing-read (format "App Name(%s):" (car names))
                                names nil t nil nil (car names)))
              (,app
               (car (remove-if
                     #'(lambda (--app)
                         (not
                          (equal (pow-app-name --app) name)))
                     apps))))
         (if (not (null ,app))
             (progn ,@body)
           (pow-error "App \"%s\" is not found" name))))))

;;;###autoload
(defun pow-unregister-current-app ()
  "Unregister a pow app for current project."
  (interactive)
  (pow-with-current-app app
    (pow-wrap-error-in-message
        (format "Unregistered app \"%s\"" (pow-app-name app))
      (pow-unregister-app app))))

;;;###autoload
(defun pow-open-current-app ()
  "Open a pow app for current project."
  (interactive)
  (pow-with-current-app app (pow-open-app app)))

;;;###autoload
(defun pow-restart-current-app ()
  "Restart a pow app for current project."
  (interactive)
  (pow-with-current-app app
    (pow-wrap-error-in-message
        (format "App \"%s\" will restart on next request" (pow-app-name app))
      (pow-restart-app app))))



;; provide
(provide 'pow-core)
;;; pow-core.el ends here