;; -*- lexical-binding: t -*-
;; Copyright (C) 2025 Marcus L. Hanestad <marlhan@proton.me>
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;; TODO: all-the-icons

(use-package request :ensure t)

(require 'request)

(setq wakatime-dashboard--base-api-url "https://api.wakatime.com/api/v1")
(setq wakatime-dashboard--buffer-name "*Wakatime Dashboard*")
(setq wakatime-dashboard--values (make-hash-table))

(defface wakatime-dashboard--title-face
  '((t (:inherit font-lock-type-face :weight bold :height 1.5)))
  "Title face")

(defface wakatime-dashboard--primary-face
  '((t (:inherit font-lock-type-face :weight bold :height 1.2)))
  "Primary face")

(defface wakatime-dashboard--secondary-face
  '((t (:inherit font-lock-function-name-face :weight bold)))
  "Secondary face")

(defun wakatime-dashboard--buffer ()
  (let ((buffer (get-buffer wakatime-dashboard--buffer-name)))
    (if buffer
        buffer
      (generate-new-buffer wakatime-dashboard--buffer-name))))

(defun wakatime-dashboard--seconds-to-string (seconds)
  (let* ((hours (/ seconds (* 60 60)))
         (minutes (/ (% seconds (* 60 60)) 60)))
    (concat
     (if (> hours 0)
       (format "%d hrs%s" hours (if (> minutes 0) " " ""))
       "")
     (if (> minutes 0)
       (format "%d mins" minutes)
       ""))))

(defun wakatime-dashboard--on-vlues-change ()
  (let ((buffer (wakatime-dashboard--buffer)))
    (with-current-buffer buffer
      (read-only-mode -1)
    (erase-buffer)
    (let ((total-time (gethash 'total-time wakatime-dashboard--values))
            (daily-average (gethash 'daily-average wakatime-dashboard--values))
            (last-week (reverse (gethash 'last-week wakatime-dashboard--values)))
            (last-week-total
             (gethash 'last-week-total wakatime-dashboard--values))
            (last-week-average
             (gethash 'last-week-average wakatime-dashboard--values))
            (projects (gethash 'projects wakatime-dashboard--values)))
      (insert (propertize "WakaTime" 'face 'wakatime-dashboard--title-face))
      (newline)
      (newline)
      (insert (propertize "All Time:" 'face 'wakatime-dashboard--primary-face))
      (newline)
      (insert (propertize "  Total: " 'face 'font-lock-keyword-face))
      (if total-time
          (insert (wakatime-dashboard--seconds-to-string total-time))
        (insert (propertize "Loading..." 'face 'font-lock-comment-face)))
      (newline)
      (insert (propertize "  Daily Average: " 'face 'font-lock-keyword-face))
      (if daily-average
          (insert (wakatime-dashboard--seconds-to-string daily-average))
        (insert (propertize "Loading..." 'face 'font-lock-comment-face)))
      (newline)
      (newline)
        (insert
        (propertize "Last 7 Days:" 'face 'wakatime-dashboard--primary-face))
        (newline)
        (insert (propertize "  Total: " 'face 'font-lock-keyword-face))
        (if last-week-total
            (insert
             (wakatime-dashboard--seconds-to-string (floor last-week-total)))
          (insert (propertize "Loading..." 'face 'font-lock-comment-face)))
        (newline)
        (insert (propertize "  Daily average: " 'face 'font-lock-keyword-face))
        (if last-week-average
            (insert last-week-average)
          (insert (propertize "Loading..." 'face 'font-lock-comment-face)))
        (newline)
        (newline)
        (insert
        (propertize "  Days:" 'face 'wakatime-dashboard--secondary-face))
        (newline)
        (if last-week
            (dolist (day last-week)
              (insert
               "    "
               (propertize
                (concat (nth 0 day) ": ")
                'face 'font-lock-keyword-face)
               (nth 1 day))
              (newline))
          (progn
            (insert (propertize "    Loading..." 'face 'font-lock-comment-face))
            (newline)))
        (newline)
        (insert
        (propertize "  Projects:" 'face 'wakatime-dashboard--secondary-face))
        (newline)
        (if projects
            (maphash (lambda (project-name value)
                       (insert "    "
                               (propertize (concat project-name ": ") 'face
                                           'font-lock-keyword-face)
                               (wakatime-dashboard--seconds-to-string
                                (floor value)))
                       (newline))
                     projects)
          (progn
            (insert (propertize "    Loading..." 'face 'font-lock-comment-face))
            (newline)
            )))
      (read-only-mode 1))))

(defun wakatime-dashboard--do-request (endpoint on-success)
  (request
    (concat wakatime-dashboard--base-api-url endpoint)
    :type
    "GET"
    :headers
    `
    (("Authorization"
      . ,(concat "Basic " (base64-encode-string wakatime-dashboard-api-key))))
    :parser 'json-read
    :success on-success
    :error (cl-function (lambda (&key error-thrown &allow-other-keys)
                        ;; TODO: Propper error reporting
                        (message "Error: %S" error-thrown)))))

(defun wakatime-dashboard--total-time ()
  (wakatime-dashboard--do-request
   "/users/current/all_time_since_today"
    (cl-function (lambda (&key data &allow-other-keys)
            (let* ((stats (assoc 'data data))
                   (total-seconds (cdr (assoc 'total_seconds stats)))
                   (daily-average (cdr (assoc 'daily_average stats))))
            (puthash 'total-time (floor total-seconds)
                     wakatime-dashboard--values)
            (puthash 'daily-average (floor daily-average)
                     wakatime-dashboard--values)
            (wakatime-dashboard--on-vlues-change))))))

(defun wakatime-dashboard--format-time (time)
  (format-time-string "%F" time))

(defun wakatime-dashboard--last-week ()
  (let* ((end (current-time))
        (start (time-subtract end (days-to-time 6))))
    (wakatime-dashboard--do-request
     (concat "/users/current/summaries" "?start="
             (wakatime-dashboard--format-time start) "&end="
             (wakatime-dashboard--format-time end))
     (cl-function (lambda (&key data &allow-other-keys)
                    (let* ((stats (cdr (assoc 'data data)))
                           (daily-average (cdr (assoc 'daily_average data)))
                           (daily-average-text (cdr (assoc 'text daily-average)))
                           (days '())
                           (total-week 0.0)
                           (projects (make-hash-table :test 'equal)))
                      (dotimes (i (length stats))
                               (let*
                                   ((range (cdr (assoc 'range (aref stats i))))
                                      (grand-total
                                       (cdr (assoc 'grand_total (aref stats i))))
                                      (total-text
                                       (cdr (assoc 'text grand-total)))
                                      (total-seconds
                                       (cdr (assoc 'total_seconds grand-total)))
                                      (day-text (cdr (assoc 'text range)))
                                      (project-list-day
                                       (cdr (assoc 'projects (aref stats i)))))
                                 (setq days
                                       (append days
                                               (list (list day-text total-text))))
                                 (setq total-week (+ total-week total-seconds))
                                 (dotimes (i (length project-list-day))
                                   (let* ((project (aref project-list-day i))
                                          (project-name
                                           (cdr (assoc 'name project)))
                                          (total-sec
                                           (cdr (assoc 'total_seconds project)))
                                          (previous
                                           (gethash project-name projects 0.0)))
                                     (puthash project-name
                                              (+ previous total-sec) projects)))))
                      (puthash 'last-week days wakatime-dashboard--values)
                      (puthash 'last-week-total total-week
                               wakatime-dashboard--values)
                      (puthash 'last-week-average daily-average-text
                               wakatime-dashboard--values)
                      (puthash 'projects projects wakatime-dashboard--values))
                      (wakatime-dashboard--on-vlues-change))))))

(defun wakatime-dashboard ()
  (interactive)
  (let ((buffer (wakatime-dashboard--buffer)))
    (switch-to-buffer buffer)
    (with-current-buffer buffer
      (font-lock-mode -1)
      (setq wakatime-dashboard--values (make-hash-table))
      (wakatime-dashboard--on-vlues-change)
      (wakatime-dashboard--total-time)
      (wakatime-dashboard--last-week))))

(provide 'wakatime-dashboard)
