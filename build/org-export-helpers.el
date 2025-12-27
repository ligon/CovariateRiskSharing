;;; org-export-helpers.el --- Export helpers for risk-sharing-results.org
;;
;; Provides org-mode export functionality without requiring external packages.
;; This ensures the replication package is self-contained.

;;; Code:

(defun org-export-ignore-headlines (data backend info)
  "Remove headlines tagged with :ignore: but keep their contents.
This provides the same functionality as ox-extra's ignore-headlines
feature without requiring the org-contrib package."
  (org-element-map data 'headline
    (lambda (headline)
      (when (member "ignore" (org-element-property :tags headline))
        (let ((contents (org-element-contents headline)))
          (mapc (lambda (el) (org-element-insert-before el headline))
                contents))
        (org-element-extract-element headline))))
  data)

;; Register the filter
(add-hook 'org-export-filter-parse-tree-functions 'org-export-ignore-headlines)

(provide 'org-export-helpers)
;;; org-export-helpers.el ends here
