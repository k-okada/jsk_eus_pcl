(require :eus_pcl "package://eus_pcl/euslisp/eus_pcl.so")

;; pcl::SacModel
(defvar pcl::*SACMODEL_PLANE* 0)
(defvar pcl::*SACMODEL_LINE*  1)
(defvar pcl::*SACMODEL_CIRCLE2D* 2)
(defvar pcl::*SACMODEL_CIRCLE3D* 3)
(defvar pcl::*SACMODEL_SPHERE* 4)
(defvar pcl::*SACMODEL_CYLINDER* 5)
(defvar pcl::*SACMODEL_CONE* 6)
(defvar pcl::*SACMODEL_TORUS* 7)
(defvar pcl::*SACMODEL_PARALLEL_LINE* 8)
(defvar pcl::*SACMODEL_PERPENDICULAR_PLANE* 9)
(defvar pcl::*SACMODEL_PARALLEL_LINES* 10)
(defvar pcl::*SACMODEL_NORMAL_PLANE* 11)
(defvar pcl::*SACMODEL_NORMAL_SPHERE* 12)
(defvar pcl::*SACMODEL_REGISTRATION* 13)
(defvar pcl::*SACMODEL_REGISTRATION_2D* 14)
(defvar pcl::*SACMODEL_PARALLEL_PLANE* 15)
(defvar pcl::*SACMODEL_NORMAL_PARALLEL_PLANE* 16)
(defvar pcl::*SACMODEL_STICK* 17)

;; method types
(defvar pcl::*SAC_RANSAC*  0)
(defvar pcl::*SAC_LMEDS*   1)
(defvar pcl::*SAC_MSAC*    2)
(defvar pcl::*SAC_RRANSAC* 3)
(defvar pcl::*SAC_RMSAC*   4)
(defvar pcl::*SAC_MLESAC*  5)
(defvar pcl::*SAC_PROSAC*  6)

;; EUS_ICP_TYPE
(defvar pcl::*REGIST_SVD*  0)
(defvar pcl::*REGIST_NL*   1)
(defvar pcl::*REGIST_GICP* 2)
(defvar pcl::*REGIST_NDT*  3)

(unless (find-package "EUS_PCL") (make-package "EUS_PCL"))
(in-package "EUS_PCL")

;;
;; euspcl_common
;;
(defun pca (point-cloud)
  (pcl::pcl-pca point-cloud))

;;;
;;; euspcl_io
;;;
(defun write-pcd (fname point-cloud &key (binary t))
  (pcl::write-pcd point-cloud fname binary))

(defun read-pcd (fname)
  (pcl::read-pcd fname))

(defun write-pcd-list (plist &optional (fmt "point~3,3D.pcd"))
  (let ((cnt 0))
    (dolist (p plist)
      (let ((fname (format nil fmt cnt)))
        (eus_pcl::write-pcd fname p))
      (incf cnt)
      )))

(defun read-pcd-list (&optional (fmt "point~3,3D.pcd") (size 1000))
  (let (ret)
    (dotimes (i size)
      (let ((fname (format nil fmt i)))
        (when (probe-file fname)
          (push (eus_pcl::read-pcd fname) ret)
          (send (car ret) :put :filename fname)
          )
        ))
    (nreverse ret)))

;;;
;;; euspcl_filters
;;;
(defun down-sample (point-cloud &key (size-x 20.0) (size-y 20.0) (size-z 20.0))
  (pcl::downsample point-cloud size-x size-y size-z))

(defun extract-indices (point-cloud indices &key (negative nil) (create t))
  (pcl::extract-indices point-cloud indices negative create))

(defun crop-box (point-cloud minpoint maxpoint &key (negative nil) (create t))
  (pcl::crop-box point-cloud minpoint maxpoint negative create))

;;;
;;; euspcl_features
;;;
(defun calc-normals (point-cloud &key (radius 30.0) (ksearch 0) (create nil))
  (pcl::add-normal point-cloud create radius ksearch))

;;;
;;; euspcl_octree
;;;
#|
max_vox = max[ (max - min)/resolution , 2]
depth = ceil (log2 (max_vox) - eps)
slen = (1 << depth) * resolution - eps
|#

;;;
;;; euspcl_sample_consensus
;;;
(defun sample-consensus-segmentation
  (point-cloud &key (model-type pcl::*SACMODEL_PLANE*)
               (method-type pcl::*SAC_RANSAC*)
               (max-iteration 10000) (min-radius lisp::most-negative-float)
               (max-radius lisp::most-positive-float)
               (distance-threshold 50) (optimization t) (negative nil)
               (return-model nil) (return-indices nil))
  (pcl::sac-segmentation point-cloud
                         model-type method-type max-iteration
                         min-radius max-radius distance-threshold
                         optimization negative return-model
                         return-indices))
(defun extract-plane (point-cloud &rest args)
  (apply #'sample-consensus-segmentation
         point-cloud args))

(defun make-plane-from-coefficients (coefficients)
  (let ((nl (subseq coefficients 0 3))
        (dist (elt coefficients 3)))
    (setq dist (* 1000.0 (/ dist (norm nl))))
    (user::make-plane :normal nl :distance dist)))

;;;
;;; euspcl_surface
;;;
(defun make-faces-from-polygon-result (point-cloud polygons)
  (let ((mat (send point-cloud :points))
        ret)
    (dolist (polygon polygons)
      (push
       (instance geo::face :init :vertices
                 (map cons #'(lambda (i) (user::c-matrix-row mat i)) polygon))
       ret))
    ret))
(defun make-faceset-from-polygon-result (point-cloud polygons)
  (instance geo::faceset :init :faces
            (make-faces-from-polygon-result point-cloud polygons)))

;;;
;;; euspcl_segmentation
;;;
(defun euclidean-clustering (point-cloud &key (min-size 500) (max-size 20000) (tolerance 20.0))
  (pcl::extract-euclidean-clusters point-cloud
                                   min-size max-size tolerance))

;;;
;;; euspcl_octomap
;;;
(defclass octomap
  :super user::pointcloud
  :slots (ptr
          resolution
          type
          depth-vec
          max-depth
          disp-id-vec
          disp-id)
  )
(defmethod octomap
  (:init (&key ((:resolution r) 50) (type)
               (max-bounding-box) (min-bounding-box))
   (setq resolution r)
   (setq ptr (pcl::octomap-create resolution))
   (sys::dispose-hook self t)
   (send-super :init)
   self)
  (:init-from-msg (msg) ;; msg is octomap_msgs/Octomap
   ;; check message type (send msg :id)
   (when (string= (send msg :id) "OcTree")
     (setq type (send msg :id))
     (setq resolution (* (send msg :resolution) 1000.0))
     (setq ptr (pcl::octomap-create
                resolution (coerce (send msg :data) string)
                (send msg :binary)))
     (if ptr self)
     ))
  ;;
  (:get-tree-depth () (pcl::octomap-get-tree-depth ptr))
  (:clear () (pcl::octomap-clear ptr))
  (:expand () (pcl::octomap-expand ptr))
  (:prune () (pcl::octomap-prune ptr))
  (:to-max-likelihood () (pcl::octomap-to-max-likelihood ptr))
  (:update-inner-occupancy () (pcl::octomap-update-inner-occupancy ptr))
  ;;
  (:dump (&optional binary) (pcl::octomap-dump-data ptr binary))
  (:resolution (&optional r) (pcl::octomap-resolution ptr r))
  (:bounding-box
   (&key (bounding-box-min) (bounding-box-max))
   (pcl::octomap-bounding-box ptr bounding-box-min bounding-box-max))
  (:bounding-box-info () (pcl::octomap-bounding-box-info ptr))
  (:clamping-threshold
   (&key (clamping-min) (clamping-max))
   (pcl::octomap-clamping-threshold ptr clamping-min clamping-max))
  (:metric-info () (pcl::octomap-metric-info ptr))
  (:occupancy-threshold (&optional thre) (pcl::octomap-occupancy-threshold ptr thre))
  (:probability (&key (hit) (miss)) (pcl::octomap-probability ptr hit miss))
  (:get-tree-info () (pcl::octomap-get-tree-info ptr))
  (:use-bounding-box-limit (&optional (enable t)) (pcl::octomap-use-bbx-limit ptr enable))
  (:number-of-nodes () (pcl::octomap-node-num ptr))
  (:add-points
   (point-cloud &key (origin (float-vector 0 0 0)))
   (pcl::octomap-add-points ptr point-cloud origin))
  (:read-nodes
   (&key (depth 0) (return-free nil) (return-both) (with-color) (multi-resolution))
   (pcl::octomap-read-nodes ptr depth return-free return-both with-color multi-resolution))
  (:update-visual
   (&key (return-both) ((:transparent tp) 0.7))
   (let* ((pt (send self :read-nodes :return-both return-both :with-color t :multi-resolution t))
          (max-depth_ (send self :get-tree-depth))
          (depth-vec_ (send pt :get :result)))
     (replace-object self pt)
     (setq max-depth max-depth_
           depth-vec depth-vec_
           user::transparent tp)
     (setq disp-id-vec (instantiate vector (+ max-depth 1)))
     self
     ))
  ;; (:points-check
  ;; (:detect-change
  (:read-unknown
   (&key (depth 0) (max-bounding-box) (min-bounding-box))
   (pcl::octomap-read-unknown ptr depth))
  (:search-ray
   (ray-origin ray-ends &key (depth 0))
   (pcl::octomap-search-ray ptr ray-origin ray-ends depth))
  (:dispose () (pcl::octomap-delete ptr))
  (:transparent (&optional tr) (when tr (setq user::transparent tr)) user::transparent)
  (:draw
   (vwer)
   ;; (send-super :draw vwer) ;; point representation
   (send self :draw-raw vwer))
  (:draw-raw (vwer) ;; overwrite
   ;;
   (gl::glPushAttrib gl::GL_ALL_ATTRIB_BITS)
   (if vwer (send vwer :viewsurface :makecurrent))
   ;;(gl::glDisable gl::GL_LIGHTING)
   ;;
   (when user::transparent
     (gl::glDepthMask gl::GL_FALSE)
     (gl::glEnable gl::GL_BLEND)
     (gl::glBlendFunc gl::GL_SRC_ALPHA gl::GL_ONE_MINUS_SRC_ALPHA))

   (gl::glpushmatrix)
   (gl::glmultmatrixf (array-entity (transpose (send user::worldcoords :4x4) gl::*temp-matrix*)))

   (let ((pos (float-vector 0 0 0))
         (col (float-vector 0 0 0))
         (pmat (send self :points))
         (cmat (send self :colors))
         (len (send self :size))
         depth)
     (gl::glpushmatrix)
     (dotimes (i len)
       (user::c-matrix-row pmat i pos)
       (setq depth (elt depth-vec i))
       ;; color
       (when cmat
         (user::c-matrix-row cmat i col)
         (gl::glColor3fv col)
         (cond
          (user::transparent
           (gl::glMaterialfv gl::GL_FRONT  gl::GL_AMBIENT_AND_DIFFUSE
                             (concatenate float-vector col (float-vector user::transparent)))
           (gl::glMaterialfv gl::GL_BACK gl::GL_AMBIENT_AND_DIFFUSE (float-vector 0 0 0 0)))
          (t
           (gl::glMaterialfv gl::GL_FRONT gl::GL_AMBIENT_AND_DIFFUSE col)
           (gl::glMaterialfv gl::GL_BACK  gl::GL_AMBIENT_AND_DIFFUSE col))
          ))
       (gl::glpushmatrix)
       (gl::gltranslatefv pos)
       (cond
        ((elt disp-id-vec depth)
         (gl::glcalllist (elt disp-id-vec depth)))
        (t
         (let* ((disp-id (gl::glgenlists 1))
                (cb-size (* resolution (expt 2 (- max-depth depth))))
                (cb (geo::make-cube cb-size cb-size cb-size)))
           (gl::glnewlist disp-id gl::gl_compile)
           (mapc #'(lambda (aface) (gl::draw-face aface nil nil)) (send cb :faces))
           (gl::glendlist)
           (setf (elt disp-id-vec depth) disp-id))
         ))
       (gl::glpopmatrix)
       )
     (gl::glpopmatrix)
     )
   (gl::glpopmatrix)

   ;;(gl::glEnable gl::GL_LIGHTING)
   (when user::transparent
     (gl::glDepthMask gl::GL_TRUE)
     (gl::glDisable gl::GL_BLEND))
   (gl::glPopAttrib)
   )
  )

;;;
;;; euspcl_kdtree
;;;
(defclass kdtree
  :super propertied-object
  :slots (ptr incloud))
(defmethod kdtree
  (:init (point-cloud)
   (setq incloud point-cloud)
   (setq ptr (pcl::kdtree-create point-cloud))
   (sys::dispose-hook self t)
   self)
  (:points (&rest args) (user::forward-message-to incloud args))
  (:number-of-points () (send incloud :size))
  (:k-search
   (point &optional (k 1)) ;; return point cloud
   (when ptr
     (let ((ret (pcl::kdtree-k-search ptr point k))
           pt)
       (when ret
         (setq pt (pcl::extract-indices incloud
                                        (car ret)
                                        nil t))
         (send pt :put :distance (cdr ret))
         (send pt :put :search-point (copy-seq point))
         pt)
       )))
  (:radius-search (point radius &optional (min-radius)) ;; retrun point cloud
   (when ptr
     (let ((ret (pcl::kdtree-r-search ptr point radius))
           pt)
       (when ret
         (when min-radius
           (let ((idx (car ret))
                 (dist (cdr ret))
                 starti)
             (dotimes (i (length idx))
               (when (>= (elt dist i) min-radius)
                 (setq starti i)
                 (return)))
             (unless starti
               (return-from :radius-search nil))
             (setq ret (cons (subseq idx starti)
                             (subseq dist starti)))
             ))
         (setq pt (pcl::extract-indices incloud
                                        (car ret)
                                        nil t))
         (send pt :put :distance (cdr ret))
         (send pt :put :search-point (copy-seq point))
         pt)
       )))
  (:search
   (point &optional (k 1)) ;; return point (k==1) or points (k/=1)
   (cond
    ((= k 1)
     (send self :nearest-neighbor point))
    (t
     (let ((ret (pcl::kdtree-k-search ptr point k)))
       (when ret
         (let ((idx (car ret))
               (pc  (send incloud :points))
               pts)
           (dotimes (i (length idx))
             (push
              (user::c-matrix-row pc (elt idx i))
              pts))
           (nreverse pts)))))
    ))
  (:nearest-neighbor (point) ;; retrun points
   (when ptr
     (let ((ret (pcl::kdtree-k-search ptr point 1)))
       (user::c-matrix-row (send incloud :points)
                           (elt (car ret) 0))
       )))
  (:dispose () (pcl::kdtree-delete ptr))
  )

(defclass dynamic-kdtree
  :super propertied-object
  :slots (n trees))
(defmethod dynamic-kdtree
  (:init ()
   (setq n 12)
   (setq trees (make-array n)))
#|
  (:insert-cloud
   (point-cloud)
   )
|#
  (:insert (pt)
   (let (j)
     (block loop
       (dotimes (i n)
         (when (null (aref trees i))
           (setq j i)
           (return-from loop)))
       ;; expand arrays if necessary
       (warn "expand the table of kd trees~%")
       (setq j n)
       (setq n (* 2 n))
       (let ((newtrees (make-array (* 2 n))))
         (dotimes (i (length trees))
           (aset newtrees i (aref trees i)))
         (setq trees newtrees))
       ) ;/loop

     ;; collect points in the smaller trees
     ;; clean points in the trees
     (let (pts)
       (dotimes (i j)
         ;; (format t "pts[~a]: ~a~%" i (send (aref trees i) :points))
         (push (send (aref trees i) :points) pts)
         (sys::dispose-hook (aref trees i) nil)
         )
       ;; (format t "new pts[~a]: ~a~%" j (cons pt pts))
       (setq pts (nreverse pts))
       (let ((p (instance user::pointcloud :init :points (list pt))))
         (when pts
           (send p :append pts :create nil))
         (aset trees j (instance kdtree :init p)))
       )
     (dotimes (i j) (aset trees i nil))
     )
   )
  (:number-of-points ()
   (let ((np 0))
     (dotimes (i n)
       (when (aref trees i)
         (setq np (+ np (send (aref trees i) :number-of-points)))))
     np)
   )
  (:nearest-neighbor (pt)
   (let ((mind lisp::most-positive-float)
         nnp)
     (dotimes (i n)
       (if (aref trees i)
           (let* ((nnp-candidate
                   ;;(car (send (aref trees i) :search pt)))
                   (send (aref trees i) :search pt 1))
                  (d (distance nnp-candidate pt)))
             (when (< d mind)
               (setq mind d nnp nnp-candidate))
             )))
     (list mind nnp))
   )
  )
(in-package "USER")
