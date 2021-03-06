// RUN: tf-opt %s -split-input-file -verify-diagnostics -tf-resource-op-lifting | FILECHECK_OPTS="" FileCheck %s

// Tests that resource load operations are hoisted.

// CHECK-LABEL: func @only_resource_load
func @only_resource_load() -> tensor<*xi32> {

  // CHECK: %[[RES_HANDLE:[0-9]*]] = "tf.VarHandleOp"
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource>

  // CHECK: %[[RES_READ_VAL:[0-9]*]] = "tf.ReadVariableOp"(%[[RES_HANDLE]])
  // CHECK: "tf_device.cluster"
  // CHECK: %[[COMPUTE_RES:[0-9]*]] = "tf.SomeComputation"(%[[RES_READ_VAL]])
  // CHECK: tf_device.return %[[COMPUTE_RES]]
  // CHECK: {cluster_attr = "cluster_attr"}
  // CHECK-SAME: () -> tensor<*xi32>

  %1 = "tf_device.cluster"() ( {
    %2 = "tf.ReadVariableOp"(%0) {dtype = i32} : (tensor<*x!tf.resource>) -> tensor<*xi32>
    %3 = "tf.SomeComputation"(%2) : (tensor<*xi32>) -> (tensor<*xi32>)
    tf_device.return %3 : tensor<*xi32>
  }) {cluster_attr = "cluster_attr"} : () -> tensor<*xi32>

  return %1 : tensor<*xi32>
}

// -----

// Tests that resource store operations are hoisted.

// CHECK-LABEL: func @only_resource_store
func @only_resource_store() -> tensor<*xi32> {

  // CHECK: %[[RES_HANDLE:[0-9]*]] = "tf.VarHandleOp"
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource>

  // CHECK: %[[CLUSTER_RES:[0-9]*]]:2 = "tf_device.cluster"
  // CHECK: %[[COMPUTE_RES:[0-9]*]] = "tf.SomeComputation"()
  // CHECK: tf_device.return %[[COMPUTE_RES]], %[[COMPUTE_RES]]
  // CHECK: {cluster_attr = "cluster_attr"}
  // CHECK-SAME: () -> (tensor<*xi32>, tensor<*xi32>)
  // CHECK: "tf.AssignVariableOp"(%[[RES_HANDLE]], %[[CLUSTER_RES]]#1)

  %1 = "tf_device.cluster"() ( {
    %2 = "tf.SomeComputation"() : () -> (tensor<*xi32>)
    "tf.AssignVariableOp"(%0, %2) {dtype = i32} : (tensor<*x!tf.resource>, tensor<*xi32>) -> ()
    tf_device.return %2 : tensor<*xi32>
  }) {cluster_attr = "cluster_attr"} : () -> tensor<*xi32>

  // CHECK: return %[[CLUSTER_RES]]#0
  return %1 : tensor<*xi32>
}

// -----

// Tests that a resource ops with both load and store are hoisted.

// CHECK-LABEL: func @same_resource_load_and_store
func @same_resource_load_and_store() -> tensor<*xi32> {

  // CHECK: %[[RES_HANDLE:[0-9]*]] = "tf.VarHandleOp"
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource>

  // CHECK: %[[RES_READ_VAL:[0-9]*]] = "tf.ReadVariableOp"(%[[RES_HANDLE]])
  // CHECK: %[[CLUSTER_RES:[0-9]*]]:2 = "tf_device.cluster"
  // CHECK: %[[COMPUTE_RES:[0-9]*]] = "tf.SomeComputation"(%[[RES_READ_VAL]])
  // CHECK: tf_device.return %[[COMPUTE_RES]], %[[COMPUTE_RES]]
  // CHECK: {cluster_attr = "cluster_attr"}
  // CHECK-SAME: () -> (tensor<*xi32>, tensor<*xi32>)
  // CHECK: "tf.AssignVariableOp"(%[[RES_HANDLE]], %[[CLUSTER_RES]]#1)

  %1 = "tf_device.cluster"() ( {
    %2 = "tf.ReadVariableOp"(%0) {dtype = i32} : (tensor<*x!tf.resource>) -> tensor<*xi32>
    %3 = "tf.SomeComputation"(%2) : (tensor<*xi32>) -> (tensor<*xi32>)
    "tf.AssignVariableOp"(%0, %3) {dtype = i32} : (tensor<*x!tf.resource>, tensor<*xi32>) -> ()
    tf_device.return %3 : tensor<*xi32>
  }) {cluster_attr = "cluster_attr"} : () -> tensor<*xi32>

  // CHECK: return %[[CLUSTER_RES]]#0
  return %1 : tensor<*xi32>
}

// -----

// Tests that internal resource operations are not hoisted.

// CHECK-LABEL: func @internal_resource
func @internal_resource() -> tensor<*xi32> {

  // CHECK: %[[CLUSTER_RES:[0-9]*]] = "tf_device.cluster"
  %0 = "tf_device.cluster"() ( {

    // CHECK: %[[RES_HANDLE:[0-9]*]] = "tf.VarHandleOp"
    %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource>

    // CHECK: %[[RES_READ_VAL:[0-9]*]] = "tf.ReadVariableOp"(%[[RES_HANDLE]])
    %2 = "tf.ReadVariableOp"(%1) {dtype = i32} : (tensor<*x!tf.resource>) -> tensor<*xi32>

    // CHECK: %[[COMPUTE_RES:[0-9]*]] = "tf.SomeComputation"(%[[RES_READ_VAL]])
    %3 = "tf.SomeComputation"(%2) : (tensor<*xi32>) -> (tensor<*xi32>)

    // CHECK: "tf.AssignVariableOp"(%[[RES_HANDLE]], %[[COMPUTE_RES]])
    "tf.AssignVariableOp"(%1, %3) {dtype = i32} : (tensor<*x!tf.resource>, tensor<*xi32>) -> ()

    // CHECK: tf_device.return %[[COMPUTE_RES]]
    tf_device.return %3 : tensor<*xi32>
  }) {cluster_attr = "cluster_attr"} : () -> tensor<*xi32>

  // CHECK: return %[[CLUSTER_RES]]
  return %0 : tensor<*xi32>
}

// -----

// Tests that pass lifts resource reads/writes from a loop, and removed unused
// resources.

// CHECK-LABEL: func @cluster_with_loop
func @cluster_with_loop() -> () {
  // CHECK: %[[COUNT:.*]] = "tf.Const"() {value = dense<10> : tensor<i32>}
  %0 = "tf.Const"() {value = dense<10> : tensor<i32>} : () -> tensor<i32>
  // CHECK: %[[VH:.*]] = "tf.VarHandleOp"()
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  %unused = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  // CHECK: %[[READ:.*]] = "tf.ReadVariableOp"(%[[VH]])
  // CHECK: %[[CLUSTER:.*]] = "tf_device.cluster"()
  "tf_device.cluster"() ( {
    // CHECK: %[[WHILE:.*]]:2 = "tf.While"(%[[COUNT]], %[[READ]])
    %2:3 = "tf.While"(%0, %1, %unused)
               {body = @while_body, cond = @while_cond, device = "", is_stateless = false}
         : (tensor<i32>, tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>)
         -> (tensor<i32>, tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>)
    // CHECK: tf_device.return %[[WHILE]]#1 : tensor<f32>
    tf_device.return
  // CHECK: {cluster_attr = "cluster_attr"} : () -> tensor<f32>
  }) {cluster_attr = "cluster_attr"} : () -> ()
  // CHECK: "tf.AssignVariableOp"(%[[VH]], %[[CLUSTER]])
  // CHECK: return
  return
}
// CHECK: func @while_body(%[[BARG0:.*]]: tensor<i32>, %[[BARG1:.*]]: tensor<f32>)
func @while_body(%arg0: tensor<i32>, %arg1: tensor<*x!tf.resource<tensor<f32>>>, %arg2: tensor<*x!tf.resource<tensor<f32>>>)
    -> (tensor<i32>, tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>) {
  %read0 = "tf.ReadVariableOp"(%arg1) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  // CHECK-NEXT: %[[ADD0:.*]] = "tf.AddV2"(%[[BARG1]], %[[BARG1]])
  %add0 = "tf.AddV2"(%read0, %read0) : (tensor<f32>, tensor<f32>) -> tensor<f32>
  "tf.AssignVariableOp"(%arg1, %add0) : (tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> ()
  %read1 = "tf.ReadVariableOp"(%arg1) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  // CHECK-NEXT: %[[ADD1:.*]] = "tf.AddV2"(%[[ADD0]], %[[ADD0]])
  %add1 = "tf.AddV2"(%read1, %read1) : (tensor<f32>, tensor<f32>) -> tensor<f32>
  "tf.AssignVariableOp"(%arg1, %add1) : (tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> ()
  // CHECK-NEXT: %[[DELTA:.*]] = "tf.Const"() {value = dense<-1> : tensor<i32>}
  %constant = "tf.Const"() {value = dense<-1> : tensor<i32>} : () -> tensor<i32>
  // CHECK-NEXT: %[[ADD2:.*]] = "tf.AddV2"(%[[BARG0]], %[[DELTA]])
  %add2 = "tf.AddV2"(%arg0, %constant) : (tensor<i32>, tensor<i32>) -> tensor<i32>
  // CHECK-NEXT: return %[[ADD2]], %[[ADD1]]
  %id = "tf.Identity"(%arg2) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<*x!tf.resource<tensor<f32>>>
  return %add2, %arg1, %id : tensor<i32>, tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>
}
// CHECK: func @while_cond(%[[CARG0:.*]]: tensor<i32>, %[[CARG1:.*]]: tensor<f32>)
func @while_cond(%arg0: tensor<i32>, %arg1: tensor<*x!tf.resource<tensor<f32>>>, %arg2: tensor<*x!tf.resource<tensor<f32>>>) -> tensor<i32> {
  // CHECK-NEXT: return %[[CARG0]]
  return %arg0 : tensor<i32>
}

// -----

// Tests that pass lifts resource reads from loop condition.

// CHECK-LABEL: func @cluster_with_loop
func @cluster_with_loop() -> () {
  // CHECK: %[[VH:.*]] = "tf.VarHandleOp"()
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  // CHECK: %[[READ:.*]] = "tf.ReadVariableOp"(%[[VH]])
  // CHECK: %[[CLUSTER:.*]] = "tf_device.cluster"()
  "tf_device.cluster"() ( {
    // CHECK: %[[WHILE:.*]] = "tf.While"(%[[READ]])
    %1 = "tf.While"(%0) {
      body = @while_body, cond = @while_cond, device = "", is_stateless = false}
         : (tensor<*x!tf.resource<tensor<f32>>>)
         -> (tensor<*x!tf.resource<tensor<f32>>>)
    // CHECK: tf_device.return %[[WHILE]] : tensor<f32>
    tf_device.return
  // CHECK: {cluster_attr = "cluster_attr"} : () -> tensor<f32>
  }) {cluster_attr = "cluster_attr"} : () -> ()
  // CHECK: "tf.AssignVariableOp"(%[[VH]], %[[CLUSTER]])
  // CHECK: return
  return
}
// CHECK: func @while_body(%[[BARG0:.*]]: tensor<f32>)
func @while_body(%arg0: tensor<*x!tf.resource<tensor<f32>>>) -> (tensor<*x!tf.resource<tensor<f32>>>) {
  // CHECK-NEXT: %[[CONST:.*]] = "tf.Const"()
  %constant = "tf.Const"() {value = dense<0.0> : tensor<f32>} : () -> tensor<f32>
  "tf.AssignVariableOp"(%arg0, %constant) : (tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> ()
  // CHECK-NEXT: return %[[CONST]]
  return %arg0 : tensor<*x!tf.resource<tensor<f32>>>
}
// CHECK: func @while_cond(%arg0: tensor<f32>)
func @while_cond(%arg0: tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32> {
  %id = "tf.Identity"(%arg0) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<*x!tf.resource<tensor<f32>>>
  %read = "tf.ReadVariableOp"(%id) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  // CHECK-NEXT: return %[[CARG0]]
  return %read : tensor<f32>
}

// -----

// Tests that pass lifts read-only resource reads from loop, but does not add
// assign after the loop.

// CHECK-LABEL: func @cluster_with_loop
func @cluster_with_loop() -> () {
  // CHECK: %[[VH:.*]] = "tf.VarHandleOp"()
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  // CHECK: %[[READ:.*]] = "tf.ReadVariableOp"(%[[VH]])
  // CHECK: "tf_device.cluster"()
  "tf_device.cluster"() ( {
    // CHECK: %[[WHILE:.*]] = "tf.While"(%[[READ]])
    %1 = "tf.While"(%0) {
      body = @while_body, cond = @while_cond, device = "", is_stateless = false}
         : (tensor<*x!tf.resource<tensor<f32>>>)
         -> (tensor<*x!tf.resource<tensor<f32>>>)
    // CHECK: tf_device.return
    tf_device.return
  // CHECK: {cluster_attr = "cluster_attr"} : () -> ()
  }) {cluster_attr = "cluster_attr"} : () -> ()
  // CHECK-NOT: "tf.AssignVariableOp"
  // CHECK: return
  return
}
// CHECK: func @while_body(%[[BARG0:.*]]: tensor<f32>)
func @while_body(%arg0: tensor<*x!tf.resource<tensor<f32>>>) -> (tensor<*x!tf.resource<tensor<f32>>>) {
  // CHECK-NEXT: return %[[BARG0]]
  return %arg0 : tensor<*x!tf.resource<tensor<f32>>>
}
// CHECK: func @while_cond(%[[CARG0:.*]]: tensor<f32>)
func @while_cond(%arg0: tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32> {
  %read = "tf.ReadVariableOp"(%arg0) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  // CHECK-NEXT: return %[[CARG0]]
  return %read : tensor<f32>
}

// -----

// Tests that pass lifts resource reads from nested loops.

// CHECK-LABEL: func @cluster_with_nested_loop
func @cluster_with_nested_loop() -> () {
  // CHECK: %[[VH:.*]] = "tf.VarHandleOp"()
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  // CHECK: %[[VH_UNUSED:.*]] = "tf.VarHandleOp"()
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  // CHECK: %[[READ:.*]] = "tf.ReadVariableOp"(%[[VH]])
  // CHECK: %[[CLUSTER:.*]] = "tf_device.cluster"()
  "tf_device.cluster"() ( {
    // CHECK: %[[WHILE:.*]] = "tf.While"(%[[READ]])
    %2:2 = "tf.While"(%0, %1) {
      body = @while_body, cond = @while_cond, device = "", is_stateless = false}
         : (tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>)
         -> (tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>)
    // CHECK: tf_device.return %[[WHILE]] : tensor<f32>
    tf_device.return
  // CHECK: {cluster_attr = "cluster_attr"} : () -> tensor<f32>
  }) {cluster_attr = "cluster_attr"} : () -> ()
  // CHECK: "tf.AssignVariableOp"(%[[VH]], %[[CLUSTER]])
  // CHECK: return
  return
}
// CHECK: func @while_body(%[[BARG0:.*]]: tensor<f32>)
func @while_body(%arg0: tensor<*x!tf.resource<tensor<f32>>>, %arg1: tensor<*x!tf.resource<tensor<f32>>>)
    -> (tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>) {
  // CHECK: %[[WHILE:.*]] = "tf.While"(%[[BARG0]])
  %0:2 = "tf.While"(%arg0, %arg1) {
    body = @while_body1, cond = @while_cond1, device = "", is_stateless = false}
       : (tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>)
       -> (tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>)
  // CHECK-NEXT: return %[[WHILE]]
  return %0#0, %0#1 : tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>
}
// CHECK: func @while_cond(%arg0: tensor<f32>)
func @while_cond(%arg0: tensor<*x!tf.resource<tensor<f32>>>, %arg1: tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32> {
  %id = "tf.Identity"(%arg0) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<*x!tf.resource<tensor<f32>>>
  %read = "tf.ReadVariableOp"(%id) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  // CHECK-NEXT: return %[[CARG0]]
  return %read : tensor<f32>
}
// CHECK: func @while_body1(%[[BARG0:.*]]: tensor<f32>)
func @while_body1(%arg0: tensor<*x!tf.resource<tensor<f32>>>, %arg1: tensor<*x!tf.resource<tensor<f32>>>)
    -> (tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>) {
  // CHECK-NEXT: %[[CONST:.*]] = "tf.Const"()
  %constant = "tf.Const"() {value = dense<0.0> : tensor<f32>} : () -> tensor<f32>
  "tf.AssignVariableOp"(%arg0, %constant) : (tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> ()
  // CHECK-NEXT: return %[[CONST]]
  return %arg0, %arg1 : tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>
}
// CHECK: func @while_cond1(%arg0: tensor<f32>)
func @while_cond1(%arg0: tensor<*x!tf.resource<tensor<f32>>>, %arg1: tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32> {
  %id = "tf.Identity"(%arg0) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<*x!tf.resource<tensor<f32>>>
  %read = "tf.ReadVariableOp"(%id) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  // CHECK-NEXT: return %[[CARG0]]
  return %read : tensor<f32>
}

// -----

// Tests that pass reports error on non-aliasing while input/output resources.

func @cluster_with_loop() -> () {
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  "tf_device.cluster"() ( {
    // expected-error@+1 {{result #0 not tied to function argument for branch @while_body}}
    %1 = "tf.While"(%0) {
      body = @while_body, cond = @while_cond, device = "", is_stateless = false}
         : (tensor<*x!tf.resource<tensor<f32>>>) -> (tensor<*x!tf.resource<tensor<f32>>>)
    tf_device.return
  }) {cluster_attr = "cluster_attr"} : () -> ()
  return
}
func @while_body(%arg0: tensor<*x!tf.resource<tensor<f32>>>) -> (tensor<*x!tf.resource<tensor<f32>>>) {
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  return %0 : tensor<*x!tf.resource<tensor<f32>>>
}
func @while_cond(%arg0: tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32> {
  %read = "tf.ReadVariableOp"(%arg0) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  return %read : tensor<f32>
}

// -----

// Tests that pass reports error on unsupported ops in loop cond.

func @cluster_with_loop() -> () {
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  "tf_device.cluster"() ( {
    // expected-error@+1 {{found resource write in loop condition.}}
    %1 = "tf.While"(%0) {
      body = @while_body, cond = @while_cond, device = "", is_stateless = false}
         : (tensor<*x!tf.resource<tensor<f32>>>) -> (tensor<*x!tf.resource<tensor<f32>>>)
    tf_device.return
  }) {cluster_attr = "cluster_attr"} : () -> ()
  return
}
func @while_body(%arg0: tensor<*x!tf.resource<tensor<f32>>>) -> (tensor<*x!tf.resource<tensor<f32>>>) {
  %constant = "tf.Const"() {value = dense<0.0> : tensor<f32>} : () -> tensor<f32>
  "tf.AssignVariableOp"(%arg0, %constant) : (tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> ()
  return %arg0 : tensor<*x!tf.resource<tensor<f32>>>
}
func @while_cond(%arg0: tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32> {
  %read = "tf.ReadVariableOp"(%arg0) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  %constant = "tf.Const"() {value = dense<0.0> : tensor<f32>} : () -> tensor<f32>
  "tf.AssignVariableOp"(%arg0, %constant) : (tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> ()
  return %read : tensor<f32>
}

// -----

// CHECK: func @cluster_with_case(%[[ARG0:.*]]: tensor<i32>) -> tensor<4xf32>
func @cluster_with_case(%arg0: tensor<i32>) -> tensor<4xf32> {
  // CHECK: %[[VH0:.*]] = "tf.VarHandleOp"()
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  // CHECK: %[[VH1:.*]] = "tf.VarHandleOp"()
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  // CHECK-DAG: %[[READ0:.*]] = "tf.ReadVariableOp"(%[[VH0]])
  // CHECK-DAG: %[[READ1:.*]] = "tf.ReadVariableOp"(%[[VH1]])
  // CHECK: %[[CLUSTER:.*]]:2 = "tf_device.cluster"()
  %2 = "tf_device.cluster"() ( {
    // CHECK: %[[CASE:.*]]:2 = "tf.Case"(%[[ARG0]], %[[READ0]], %[[READ1]])
    %3:2 = "tf.Case"(%arg0, %0, %1) {branches = [@branch_0, @branch_1, @branch_2], is_stateless = false}
      : (tensor<i32>, tensor<*x!tf.resource<tensor<4xf32>>>, tensor<*x!tf.resource<tensor<4xf32>>>)
      -> (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>)
    // CHECK-NEXT: %[[ADD:.*]] = "tf.AddV2"(%[[CASE]]#1, %[[CASE]]#0)
    %4 = "tf.ReadVariableOp"(%3#0) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
    %5 = "tf.AddV2"(%4, %3#1) : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
    // CHECK-NEXT: tf_device.return %[[ADD]], %[[CASE]]#1
    tf_device.return %5 : tensor<4xf32>
  // CHECK: {cluster_attr = "cluster_attr"} : () -> (tensor<4xf32>, tensor<4xf32>)
  }) {cluster_attr = "cluster_attr"} : () -> tensor<4xf32>
  // CHECK: "tf.AssignVariableOp"(%[[VH0]], %[[CLUSTER]]#1)
  // CHECK: return %[[CLUSTER]]#0
  return %2 : tensor<4xf32>
}
// CHECK: func @branch_0(%[[TARG0:.*]]: tensor<4xf32>, %[[TARG1:.*]]: tensor<4xf32>)
func @branch_0(%arg0: tensor<*x!tf.resource<tensor<4xf32>>>, %arg1: tensor<*x!tf.resource<tensor<4xf32>>>)
    -> (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) {
  // CHECK-NEXT: %[[CONST:.*]] = "tf.Const"()
  %constant = "tf.Const"() {value = dense<0.0> : tensor<4xf32>} : () -> tensor<4xf32>
  "tf.AssignVariableOp"(%arg0, %constant) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
  // CHECK-NEXT: return %[[CONST]], %[[CONST]]
  return %arg0, %constant : tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>
}
// CHECK: func @branch_1(%[[EARG0:.*]]: tensor<4xf32>, %[[EARG1:.*]]: tensor<4xf32>)
func @branch_1(%arg0: tensor<*x!tf.resource<tensor<4xf32>>>, %arg1: tensor<*x!tf.resource<tensor<4xf32>>>)
    -> (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) {
  %id = "tf.Identity"(%arg1) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<*x!tf.resource<tensor<4xf32>>>
  %read = "tf.ReadVariableOp"(%id) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
  "tf.AssignVariableOp"(%arg0, %read) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
  // CHECK-NEXT: return %[[EARG1]], %[[EARG1]]
  return %arg0, %read : tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>
}
// CHECK: func @branch_2(%[[EARG0:.*]]: tensor<4xf32>, %[[EARG1:.*]]: tensor<4xf32>)
func @branch_2(%arg0: tensor<*x!tf.resource<tensor<4xf32>>>, %arg1: tensor<*x!tf.resource<tensor<4xf32>>>)
    -> (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) {
  %id = "tf.Identity"(%arg1) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<*x!tf.resource<tensor<4xf32>>>
  %read = "tf.ReadVariableOp"(%id) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
  "tf.AssignVariableOp"(%arg0, %read) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
  // CHECK-NEXT: return %[[EARG1]], %[[EARG1]]
  return %arg0, %read : tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>
}

// -----

// Tests that pass lifts resource reads from if branches.

// CHECK: func @cluster_with_if(%[[ARG0:.*]]: tensor<i1>) -> tensor<4xf32>
func @cluster_with_if(%arg0: tensor<i1>) -> tensor<4xf32> {
  // CHECK: %[[VH0:.*]] = "tf.VarHandleOp"()
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  // CHECK: %[[VH1:.*]] = "tf.VarHandleOp"()
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  // CHECK-DAG: %[[READ0:.*]] = "tf.ReadVariableOp"(%[[VH0]])
  // CHECK-DAG: %[[READ1:.*]] = "tf.ReadVariableOp"(%[[VH1]])
  // CHECK: %[[CLUSTER:.*]]:2 = "tf_device.cluster"()
  %2 = "tf_device.cluster"() ( {
    // CHECK: %[[IF:.*]]:2 = "tf.If"(%[[ARG0]], %[[READ0]], %[[READ1]])
    %3:2 = "tf.If"(%arg0, %0, %1) {then_branch = @if_then, else_branch = @if_else,
        is_stateless = false}
      : (tensor<i1>, tensor<*x!tf.resource<tensor<4xf32>>>, tensor<*x!tf.resource<tensor<4xf32>>>)
      -> (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>)
    // CHECK-NEXT: %[[ADD:.*]] = "tf.AddV2"(%[[IF]]#1, %[[IF]]#0)
    %4 = "tf.ReadVariableOp"(%3#0) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
    %5 = "tf.AddV2"(%4, %3#1) : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
    // CHECK-NEXT: tf_device.return %[[ADD]], %[[IF]]#1
    tf_device.return %5 : tensor<4xf32>
  // CHECK: {cluster_attr = "cluster_attr"} : () -> (tensor<4xf32>, tensor<4xf32>)
  }) {cluster_attr = "cluster_attr"} : () -> tensor<4xf32>
  // CHECK: "tf.AssignVariableOp"(%[[VH0]], %[[CLUSTER]]#1)
  // CHECK: return %[[CLUSTER]]#0
  return %2 : tensor<4xf32>
}
// CHECK: func @if_then(%[[TARG0:.*]]: tensor<4xf32>, %[[TARG1:.*]]: tensor<4xf32>)
func @if_then(%arg0: tensor<*x!tf.resource<tensor<4xf32>>>, %arg1: tensor<*x!tf.resource<tensor<4xf32>>>)
    -> (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) {
  // CHECK-NEXT: %[[CONST:.*]] = "tf.Const"()
  %constant = "tf.Const"() {value = dense<0.0> : tensor<4xf32>} : () -> tensor<4xf32>
  "tf.AssignVariableOp"(%arg0, %constant) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
  // CHECK-NEXT: return %[[CONST]], %[[CONST]]
  return %arg0, %constant : tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>
}
// CHECK: func @if_else(%[[EARG0:.*]]: tensor<4xf32>, %[[EARG1:.*]]: tensor<4xf32>)
func @if_else(%arg0: tensor<*x!tf.resource<tensor<4xf32>>>, %arg1: tensor<*x!tf.resource<tensor<4xf32>>>)
    -> (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) {
  %id = "tf.Identity"(%arg1) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<*x!tf.resource<tensor<4xf32>>>
  %read = "tf.ReadVariableOp"(%id) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
  "tf.AssignVariableOp"(%arg0, %read) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
  // CHECK-NEXT: return %[[EARG1]], %[[EARG1]]
  return %arg0, %read : tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>
}

// -----

// Tests that pass lifts resource reads from nested if ops.

// CHECK: func @cluster_with_nested_if(%[[ARG0:.*]]: tensor<i1>) -> tensor<f32>
func @cluster_with_nested_if(%arg0: tensor<i1>) -> tensor<f32> {
  // CHECK: %[[VH0:.*]] = "tf.VarHandleOp"()
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  // CHECK: %[[VH1:.*]] = "tf.VarHandleOp"()
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  // CHECK-DAG: %[[READ0:.*]] = "tf.ReadVariableOp"(%[[VH0]])
  // CHECK: %[[CLUSTER:.*]]:2 = "tf_device.cluster"()
  %2 = "tf_device.cluster"() ( {
    // CHECK: %[[IF:.*]] = "tf.If"(%[[ARG0]], %[[READ0]])
    %3 = "tf.If"(%arg0, %0, %1) {then_branch = @if_then, else_branch = @if_else,
        is_stateless = false}
      : (tensor<i1>, tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>)
      -> (tensor<*x!tf.resource<tensor<f32>>>)
    // CHECK-NEXT: %[[ADD:.*]] = "tf.AddV2"(%[[IF]], %[[IF]])
    %4 = "tf.ReadVariableOp"(%3) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
    %5 = "tf.AddV2"(%4, %4) : (tensor<f32>, tensor<f32>) -> tensor<f32>
    // CHECK-NEXT: tf_device.return %[[ADD]], %[[IF]]
    tf_device.return %5 : tensor<f32>
  // CHECK: {cluster_attr = "cluster_attr"} : () -> (tensor<f32>, tensor<f32>)
  }) {cluster_attr = "cluster_attr"} : () -> tensor<f32>
  // CHECK: "tf.AssignVariableOp"(%[[VH0]], %[[CLUSTER]]#1)
  // CHECK: return %[[CLUSTER]]#0
  return %2 : tensor<f32>
}
// CHECK: func @if_then(%[[TARG0:.*]]: tensor<f32>)
func @if_then(%arg0: tensor<*x!tf.resource<tensor<f32>>>, %arg1: tensor<*x!tf.resource<tensor<f32>>>)
    -> (tensor<*x!tf.resource<tensor<f32>>>) {
  // CHECK-NEXT: %[[IIF:.*]] = "tf.If"(%[[TARG0]], %[[TARG0]])
  %read = "tf.ReadVariableOp"(%arg0) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  %3 = "tf.If"(%read, %arg0) {then_branch = @inner_if_then, else_branch = @inner_if_else,
      is_stateless = false}
    : (tensor<f32>, tensor<*x!tf.resource<tensor<f32>>>)
    -> (tensor<*x!tf.resource<tensor<f32>>>)
  // CHECK-NEXT: return %[[IIF]]
  return %3 : tensor<*x!tf.resource<tensor<f32>>>
}
// CHECK: func @if_else(%[[EARG0:.*]]: tensor<f32>)
func @if_else(%arg0: tensor<*x!tf.resource<tensor<f32>>>, %arg1: tensor<*x!tf.resource<tensor<f32>>>)
    -> (tensor<*x!tf.resource<tensor<f32>>>) {
  // CHECK-NEXT: return %[[EARG0]]
  return %arg0 : tensor<*x!tf.resource<tensor<f32>>>
}
// CHECK: func @inner_if_then(%[[ITARG0:.*]]: tensor<f32>)
func @inner_if_then(%arg0: tensor<*x!tf.resource<tensor<f32>>>)
    -> (tensor<*x!tf.resource<tensor<f32>>>) {
  // CHECK-NEXT: %[[CONST:.*]] = "tf.Const"()
  %constant = "tf.Const"() {value = dense<0.0> : tensor<f32>} : () -> tensor<f32>
  "tf.AssignVariableOp"(%arg0, %constant) : (tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> ()
  // CHECK-NEXT: return %[[CONST]]
  return %arg0 : tensor<*x!tf.resource<tensor<f32>>>
}
// CHECK: func @inner_if_else(%[[IEARG0:.*]]: tensor<f32>)
func @inner_if_else(%arg0: tensor<*x!tf.resource<tensor<f32>>>)
    -> (tensor<*x!tf.resource<tensor<f32>>>) {
  // CHECK-NEXT: return %[[IEARG0]]
  return %arg0 : tensor<*x!tf.resource<tensor<f32>>>
}

// -----

// Tests that the pass reports error for ambiguous resource aliasing.

func @cluster_with_if(%arg0: tensor<i1>) -> tensor<4xf32> {
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  %2 = "tf_device.cluster"() ( {
    // expected-error @+1 {{result #0 is not tied to the same argument across all branches}}
    %3 = "tf.If"(%arg0, %0, %1) {then_branch = @if_then, else_branch = @if_else,
        is_stateless = false}
      : (tensor<i1>, tensor<*x!tf.resource<tensor<4xf32>>>, tensor<*x!tf.resource<tensor<4xf32>>>)
      -> (tensor<*x!tf.resource<tensor<4xf32>>>)
    %4 = "tf.ReadVariableOp"(%3) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
    tf_device.return %4 : tensor<4xf32>
  }) {cluster_attr = "cluster_attr"} : () -> tensor<4xf32>
  return %2 : tensor<4xf32>
}
func @if_then(%arg0: tensor<*x!tf.resource<tensor<4xf32>>>, %arg1: tensor<*x!tf.resource<tensor<4xf32>>>)
    -> (tensor<*x!tf.resource<tensor<4xf32>>>) {
  return %arg0 : tensor<*x!tf.resource<tensor<4xf32>>>
}
func @if_else(%arg0: tensor<*x!tf.resource<tensor<4xf32>>>, %arg1: tensor<*x!tf.resource<tensor<4xf32>>>)
    -> (tensor<*x!tf.resource<tensor<4xf32>>>) {
  return %arg1 : tensor<*x!tf.resource<tensor<4xf32>>>
}

// -----

// Tests that the pass reports error if output does not alias input.

func @cluster_with_if(%arg0: tensor<i1>) -> tensor<4xf32> {
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  %2 = "tf_device.cluster"() ( {
    // expected-error @+1 {{result #0 not tied to function argument for branch @if_then}}
    %3 = "tf.If"(%arg0, %0, %1) {then_branch = @if_then, else_branch = @if_else,
        is_stateless = false}
      : (tensor<i1>, tensor<*x!tf.resource<tensor<4xf32>>>, tensor<*x!tf.resource<tensor<4xf32>>>)
      -> (tensor<*x!tf.resource<tensor<4xf32>>>)
    %4 = "tf.ReadVariableOp"(%3) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
    tf_device.return %4 : tensor<4xf32>
  }) {cluster_attr = "cluster_attr"} : () -> tensor<4xf32>
  return %2 : tensor<4xf32>
}
func @if_then(%arg0: tensor<*x!tf.resource<tensor<4xf32>>>, %arg1: tensor<*x!tf.resource<tensor<4xf32>>>)
    -> (tensor<*x!tf.resource<tensor<4xf32>>>) {
  %0 = "tf.foo"(%arg0) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<*x!tf.resource<tensor<4xf32>>>
  return %0 : tensor<*x!tf.resource<tensor<4xf32>>>
}
func @if_else(%arg0: tensor<*x!tf.resource<tensor<4xf32>>>, %arg1: tensor<*x!tf.resource<tensor<4xf32>>>)
    -> (tensor<*x!tf.resource<tensor<4xf32>>>) {
  %0 = "tf.bar"(%arg0) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<*x!tf.resource<tensor<4xf32>>>
  return %0 : tensor<*x!tf.resource<tensor<4xf32>>>
}

// -----

// Tests that the pass lifts resources on two partitioned call ops sharing the
// same callee. The lifting should clone the callee then modify the clone.

// CHECK-LABEL: @cluster_with_partitioned_call
func @cluster_with_partitioned_call() -> tensor<f32> {
  // CHECK: %[[VH:.*]] = "tf.VarHandleOp"()
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  // CHECK: %[[CONST:.*]] = "tf.Const"()
  %1 = "tf.Const"() {value = dense<10.0> : tensor<f32>} : () -> tensor<f32>
  // CHECK: %[[READ:.*]] = "tf.ReadVariableOp"(%[[VH]])
  // CHECK: %[[CLUSTER:.*]] = "tf_device.cluster"()
  %2 = "tf_device.cluster"() ( {
    // CHECK: %[[PC0:.*]] = "tf.PartitionedCall"(%[[CONST]], %[[READ]], %[[CONST]])
    // CHECK-SAME: f = @callee_resource_lifted
    %3 = "tf.PartitionedCall"(%1, %0, %1) {f = @callee, config = "", config_proto = "", executor_type = ""}
      : (tensor<f32>, tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> tensor<f32>
    // CHECK: %[[PC1:.*]] = "tf.PartitionedCall"(%[[CONST]], %[[READ]], %[[CONST]])
    // CHECK-SAME: f = @callee_resource_lifted
    %4 = "tf.PartitionedCall"(%1, %0, %1) {f = @callee, config = "", config_proto = "", executor_type = ""}
      : (tensor<f32>, tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> tensor<f32>
    // CHECK: %[[ADD:.*]] = "tf.AddV2"(%[[PC0]], %[[PC1]])
    %5 = "tf.AddV2"(%3, %4) : (tensor<f32>, tensor<f32>) -> tensor<f32>
    // CHECK: tf_device.return %[[ADD]] : tensor<f32>
    tf_device.return %5 : tensor<f32>
  }) {cluster_attr = "cluster_attr"} : () -> tensor<f32>
  return %2 : tensor<f32>
}
// CHECK: @callee(%[[OA0:.*]]: tensor<f32>, %[[OA1:.*]]: tensor<*x!tf.resource<tensor<f32>>>, %[[OA2:.*]]: tensor<f32>) -> tensor<f32>
func @callee(%arg0: tensor<f32>, %arg1: tensor<*x!tf.resource<tensor<f32>>>, %arg2: tensor<f32>) -> tensor<f32> {
  // CHECK: "tf.ReadVariableOp"(%[[OA1]])
  %0 = "tf.ReadVariableOp"(%arg1) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  %1 = "tf.AddV2"(%0, %arg0) : (tensor<f32>, tensor<f32>) -> tensor<f32>
  %2 = "tf.AddV2"(%1, %arg2) : (tensor<f32>, tensor<f32>) -> tensor<f32>
  return %2 : tensor<f32>
}
// CHECK: func @callee_resource_lifted(%[[A0:.*]]: tensor<f32>, %[[A1:.*]]: tensor<f32>, %[[A2:.*]]: tensor<f32>) -> tensor<f32>
// CHECK-NEXT:   %[[ADD0:.*]] = "tf.AddV2"(%[[A1]], %[[A0]])
// CHECK-NEXT:   %[[ADD1:.*]] = "tf.AddV2"(%[[ADD0]], %[[A2]])
// CHECK-NEXT:   return %[[ADD1]]


// -----

// Tests that the pass lifts resources on two stateful partitioned call ops
// sharing the same callee. The lifting should clone the callee then modify the
// clone.

// CHECK-LABEL: @cluster_with_stateful_partitioned_call
func @cluster_with_stateful_partitioned_call() -> () {
  // CHECK: %[[VH0:.*]] = "tf.VarHandleOp"()
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  // CHECK: %[[VH1:.*]] = "tf.VarHandleOp"()
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  // CHECK: %[[CONST:.*]] = "tf.Const"()
  %2 = "tf.Const"() {value = dense<10.0> : tensor<f32>} : () -> tensor<f32>
  // CHECK-DAG: %[[READ0:.*]] = "tf.ReadVariableOp"(%[[VH0]])
  // CHECK-DAG: %[[READ1:.*]] = "tf.ReadVariableOp"(%[[VH1]])
  // CHECK: %[[CLUSTER:.*]] = "tf_device.cluster"()
  "tf_device.cluster"() ( {
    // CHECK: %[[PC0:.*]] = "tf.StatefulPartitionedCall"(%[[READ0]], %[[READ1]], %[[CONST]])
    // CHECK-SAME: f = @callee_resource_lifted
    %3 = "tf.StatefulPartitionedCall"(%0, %1, %2) {f = @callee, config = "", config_proto = "", executor_type = ""}
      : (tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> tensor<*x!tf.resource<tensor<f32>>>
    // CHECK: %[[PC1:.*]] = "tf.StatefulPartitionedCall"(%[[PC0]], %[[READ1]], %[[CONST]])
    // CHECK-SAME: f = @callee_resource_lifted
    %4 = "tf.StatefulPartitionedCall"(%3, %1, %2) {f = @callee, config = "", config_proto = "", executor_type = ""}
      : (tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> tensor<*x!tf.resource<tensor<f32>>>
    // CHECK: tf_device.return %[[PC1]] : tensor<f32>
    tf_device.return
    // CHECK: {cluster_attr = "cluster_attr"} : () -> tensor<f32>
  }) {cluster_attr = "cluster_attr"} : () -> ()
  // CHECK: "tf.AssignVariableOp"(%[[VH0]], %[[CLUSTER]])
  return
}
// CHECK: @callee(%[[OA0:.*]]: tensor<*x!tf.resource<tensor<f32>>>, %[[OA1:.*]]: tensor<*x!tf.resource<tensor<f32>>>, %[[OA2:.*]]: tensor<f32>) -> tensor<*x!tf.resource<tensor<f32>>>
func @callee(%arg0: tensor<*x!tf.resource<tensor<f32>>>, %arg1: tensor<*x!tf.resource<tensor<f32>>>, %arg2: tensor<f32>) -> tensor<*x!tf.resource<tensor<f32>>> {
  // CHECK: "tf.ReadVariableOp"(%[[OA1]])
  %0 = "tf.ReadVariableOp"(%arg1) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  %1 = "tf.AddV2"(%0, %arg2) : (tensor<f32>, tensor<f32>) -> tensor<f32>
  "tf.AssignVariableOp"(%arg0, %1) {dtype = i32} : (tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> ()
  return %arg0 : tensor<*x!tf.resource<tensor<f32>>>
}
// CHECK: func @callee_resource_lifted(%[[A0:.*]]: tensor<f32>, %[[A1:.*]]: tensor<f32>, %[[A2:.*]]: tensor<f32>) -> tensor<f32>
// CHECK-NEXT:   %[[ADD:.*]] = "tf.AddV2"(%[[A1]], %[[A2]])
// CHECK-NEXT:   return %[[ADD]]


// -----

// Tests that the pass reports error on called function that has resource output
// which doesn't alias an input.

func @cluster_with_stateful_partitioned_call() -> () {
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  %2 = "tf.Const"() {value = dense<10.0> : tensor<f32>} : () -> tensor<f32>
  "tf_device.cluster"() ( {
    %3 = "tf.StatefulPartitionedCall"(%0, %1, %2) {f = @callee, config = "", config_proto = "", executor_type = ""}
      : (tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> tensor<*x!tf.resource<tensor<f32>>>
    %4 = "tf.StatefulPartitionedCall"(%3, %1, %2) {f = @callee, config = "", config_proto = "", executor_type = ""}
      : (tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> tensor<*x!tf.resource<tensor<f32>>>
    tf_device.return
  }) {cluster_attr = "cluster_attr"} : () -> ()
  return
}
// expected-error @+1 {{unsupported function call: resource return value does not alias an input.}}
func @callee(%arg0: tensor<*x!tf.resource<tensor<f32>>>, %arg1: tensor<*x!tf.resource<tensor<f32>>>, %arg2: tensor<f32>) -> tensor<*x!tf.resource<tensor<f32>>> {
  %0 = "tf._Unknown_"() : () -> tensor<*x!tf.resource<tensor<f32>>>
  return %0 : tensor<*x!tf.resource<tensor<f32>>>
}

// -----

// Tests call op where it's result is the result of a tf.ReadVariableOp.

// CHECK-LABEL: func @call_with_forwarded_read_only_result
// CHECK-SAME: (%[[RESOURCE_ARG0:.*]]: tensor<*x!tf.resource<tensor<f32>>>)
func @call_with_forwarded_read_only_result(%arg0: tensor<*x!tf.resource<tensor<f32>>>) {
  // CHECK: %[[READ:.*]] = "tf.ReadVariableOp"(%[[RESOURCE_ARG0]])
  %0 = "tf_device.cluster"() ( {
    // CHECK: %[[CALL:.*]] = "tf.StatefulPartitionedCall"(%[[READ]])
    %1 = "tf.StatefulPartitionedCall"(%arg0) {config = "", config_proto = "", executor_type = "", f = @callee} : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
    // CHECK-NEXT: tf_device.return %[[CALL]]
    tf_device.return %1 : tensor<f32>
  }) {} : () -> tensor<f32>
  return
}

func @callee(%arg0: tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32> {
  %0 = "tf.ReadVariableOp"(%arg0) {device = ""} : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
  %1 = "tf.Identity"(%0) {device = ""} : (tensor<f32>) -> tensor<f32>
  return %1 : tensor<f32>
}

// CHECK:      func @callee_resource_lifted(%[[A0:.*]]: tensor<f32>) -> tensor<f32>
// CHECK-NEXT:   return %[[A0]]

// -----

// Test that the pass can lift resources out of IfRegion
// CHECK: func @cluster_with_ifregion(%[[ARG0:.*]]: tensor<i1>) -> tensor<4xf32>
func @cluster_with_ifregion(%arg0: tensor<i1>) -> tensor<4xf32> {
  // CHECK: %[[VH0:.*]] = "tf.VarHandleOp"()
  // CHECK: %[[VH1:.*]] = "tf.VarHandleOp"()
  // CHECK: %[[READ1:.*]] = "tf.ReadVariableOp"(%[[VH1]])
  // CHECK: %[[CLUSTER:.*]]:2 = "tf_device.cluster"()
  // CHECK: %[[IF:.*]]:2 = "tf.IfRegion"(%[[ARG0]])
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  %2 = "tf_device.cluster"() ( {
    %3:2 = "tf.IfRegion"(%arg0) ({
          // CHECK-NEXT: %[[CONST:.*]] = "tf.Const"()
          // CHECK-NEXT: "tf.Yield"(%[[CONST]], %[[CONST]])
          %constant = "tf.Const"() {value = dense<0.0> : tensor<4xf32>} : () -> tensor<4xf32>
          "tf.AssignVariableOp"(%0, %constant) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
          "tf.Yield"(%0, %constant) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
      }, {
          // CHECK: "tf.Yield"(%[[READ1]], %[[READ1]])
          %id = "tf.Identity"(%1) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<*x!tf.resource<tensor<4xf32>>>
          %read = "tf.ReadVariableOp"(%id) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
          "tf.AssignVariableOp"(%0, %read) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
          "tf.Yield"(%0, %read) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
      }) {is_stateless = false} : (tensor<i1>) -> (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>)
    // CHECK: %[[ADD:.*]] = "tf.AddV2"(%[[IF]]#1, %[[IF]]#0)
    // CHECK-NEXT: tf_device.return %[[ADD]], %[[IF]]#1
    %4 = "tf.ReadVariableOp"(%3#0) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
    %5 = "tf.AddV2"(%4, %3#1) : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
    tf_device.return %5 : tensor<4xf32>
  }) {cluster_attr = "cluster_attr"} : () -> tensor<4xf32>
  // CHECK: {cluster_attr = "cluster_attr"} : () -> (tensor<4xf32>, tensor<4xf32>)
  // CHECK: "tf.AssignVariableOp"(%[[VH0]], %[[CLUSTER]]#1)
  // CHECK: return %[[CLUSTER]]#0
  return %2 : tensor<4xf32>
}

// Test that the pass can lift resources out of CaseRegion
// CHECK: func @cluster_with_caseregion(%[[ARG0:.*]]: tensor<i32>) -> tensor<4xf32>
func @cluster_with_caseregion(%arg0: tensor<i32>) -> tensor<4xf32> {
  // CHECK: %[[VH0:.*]] = "tf.VarHandleOp"()
  // CHECK: %[[VH1:.*]] = "tf.VarHandleOp"()
  // CHECK: %[[READ1:.*]] = "tf.ReadVariableOp"(%[[VH1]])
  // CHECK: %[[CLUSTER:.*]]:2 = "tf_device.cluster"()
  // CHECK: %[[CASE:.*]]:2 = "tf.CaseRegion"(%[[ARG0]])
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  %2 = "tf_device.cluster"() ( {
    %3:2 = "tf.CaseRegion"(%arg0) ({
          // CHECK-NEXT: %[[CONST:.*]] = "tf.Const"()
          // CHECK-NEXT: "tf.Yield"(%[[CONST]], %[[CONST]])
          %constant = "tf.Const"() {value = dense<0.0> : tensor<4xf32>} : () -> tensor<4xf32>
          "tf.AssignVariableOp"(%0, %constant) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
          "tf.Yield"(%0, %constant) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
      }, {
          // CHECK: "tf.Yield"(%[[READ1]], %[[READ1]])
          %id = "tf.Identity"(%1) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<*x!tf.resource<tensor<4xf32>>>
          %read = "tf.ReadVariableOp"(%id) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
          "tf.AssignVariableOp"(%0, %read) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
          "tf.Yield"(%0, %read) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
      }, {
          // CHECK: %[[CONST1:.*]] = "tf.Const"
          // CHECK: %[[SUB:.*]] = "tf.Sub"(%[[READ1]], %[[CONST1]])
          // CHECK: "tf.Yield"(%[[READ1]], %[[SUB]])
          %id = "tf.Identity"(%1) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<*x!tf.resource<tensor<4xf32>>>
          %read = "tf.ReadVariableOp"(%id) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
          %constant = "tf.Const"() {value = dense<1.0> : tensor<4xf32>} : () -> tensor<4xf32>
          %sub = "tf.Sub"(%read, %constant) : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
          "tf.AssignVariableOp"(%0, %sub) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
          "tf.Yield"(%0, %read) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
      }) {is_stateless = false} : (tensor<i32>) -> (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>)
    // CHECK: %[[ADD:.*]] = "tf.AddV2"(%[[CASE]]#1, %[[CASE]]#0)
    // CHECK-NEXT: tf_device.return %[[ADD]], %[[CASE]]#1
    %4 = "tf.ReadVariableOp"(%3#0) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
    %5 = "tf.AddV2"(%4, %3#1) : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
    tf_device.return %5 : tensor<4xf32>
  }) {cluster_attr = "cluster_attr"} : () -> tensor<4xf32>
  // CHECK: {cluster_attr = "cluster_attr"} : () -> (tensor<4xf32>, tensor<4xf32>)
  // CHECK: "tf.AssignVariableOp"(%[[VH0]], %[[CLUSTER]]#1)
  // CHECK: return %[[CLUSTER]]#0
  return %2 : tensor<4xf32>
}

// -----

// Test that the pass can lift resources out of WhileRegion
// CHECK-LABEL: func @cluster_with_whileregion
func @cluster_with_whileregion() -> () {
  // CHECK: %[[COUNT:.*]] = "tf.Const"() {value = dense<10> : tensor<i32>}
  // CHECK: %[[VH:.*]] = "tf.VarHandleOp"()
  // CHECK: %[[READ:.*]] = "tf.ReadVariableOp"(%[[VH]])
  // CHECK: %[[CLUSTER:.*]] = "tf_device.cluster"()
  // CHECK: %[[WHILE:.*]]:2 = "tf.WhileRegion"(%[[COUNT]], %[[READ]])
  %0 = "tf.Const"() {value = dense<10> : tensor<i32>} : () -> tensor<i32>
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  %unused = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<f32>>>
  "tf_device.cluster"() ( {
    %2:3 = "tf.WhileRegion"(%0, %1, %unused) ({
            // CHECK: (%[[CARG0:.+]]: tensor<i32>, %[[CARG1:.+]]: tensor<f32>):
            // CHECK: %[[CAST:.+]] = "tf.Cast"(%[[CARG1]])
            // CHECK: "tf.Less"(%[[CARG0]], %[[CAST]])
            // CHECK: "tf.Yield"
            ^bb0(%carg0: tensor<i32>, %carg1:tensor<*x!tf.resource<tensor<f32>>>, %carg2: tensor<*x!tf.resource<tensor<f32>>>):
               %read0 = "tf.ReadVariableOp"(%carg1) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
               %cast = "tf.Cast"(%read0) : (tensor<f32>) -> tensor<i32>
               %cond = "tf.Less"(%carg0, %cast) : (tensor<i32>, tensor<i32>) -> tensor<i1>
               "tf.Yield"(%cond) : (tensor<i1>) -> ()
            }, {
            // CHECK: (%[[BARG0:.+]]: tensor<i32>, %[[BARG1:.+]]: tensor<f32>):
            // CHECK: %[[ADD0:.*]] = "tf.AddV2"(%[[BARG1]], %[[BARG1]])
            // CHECK-NEXT: %[[ADD1:.*]] = "tf.AddV2"(%[[ADD0]], %[[ADD0]])
            // CHECK-NEXT: %[[DELTA:.*]] = "tf.Const"() {value = dense<-1> : tensor<i32>}
            // CHECK-NEXT: %[[ADD2:.*]] = "tf.AddV2"(%[[BARG0]], %[[DELTA]])
            // CHECK-NEXT: "tf.Yield"(%[[ADD2]], %[[ADD1]])
            ^bb1(%barg0: tensor<i32>, %barg1:tensor<*x!tf.resource<tensor<f32>>>, %barg2: tensor<*x!tf.resource<tensor<f32>>>):
              %read0 = "tf.ReadVariableOp"(%barg1) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
              %add0 = "tf.AddV2"(%read0, %read0) : (tensor<f32>, tensor<f32>) -> tensor<f32>
              "tf.AssignVariableOp"(%barg1, %add0) : (tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> ()
              %read1 = "tf.ReadVariableOp"(%barg1) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<f32>
              %add1 = "tf.AddV2"(%read1, %read1) : (tensor<f32>, tensor<f32>) -> tensor<f32>
              "tf.AssignVariableOp"(%barg1, %add1) : (tensor<*x!tf.resource<tensor<f32>>>, tensor<f32>) -> ()
              %constant = "tf.Const"() {value = dense<-1> : tensor<i32>} : () -> tensor<i32>
              %add2 = "tf.AddV2"(%barg0, %constant) : (tensor<i32>, tensor<i32>) -> tensor<i32>
              %id = "tf.Identity"(%barg2) : (tensor<*x!tf.resource<tensor<f32>>>) -> tensor<*x!tf.resource<tensor<f32>>>
              "tf.Yield"(%add2, %barg1, %id) : (tensor<i32>, tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>) -> ()
            }) {device = "", is_stateless = false}
         : (tensor<i32>, tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>)
         -> (tensor<i32>, tensor<*x!tf.resource<tensor<f32>>>, tensor<*x!tf.resource<tensor<f32>>>)
    tf_device.return
  }) {cluster_attr = "cluster_attr"} : () -> ()
  // CHECK: tf_device.return %[[WHILE]]#1 : tensor<f32>
  // CHECK: {cluster_attr = "cluster_attr"} : () -> tensor<f32>
  // CHECK: "tf.AssignVariableOp"(%[[VH]], %[[CLUSTER]])
  // CHECK: return
  return
}

// -----

// Test that the pass can lift out recursively (If with another if it its body)
// CHECK: func @cluster_with_if_within_if(%[[ARG0:.*]]: tensor<i1>, %[[ARG1:.*]]: tensor<i1>) -> tensor<4xf32>
func @cluster_with_if_within_if(%arg0: tensor<i1>, %arg1: tensor<i1>) -> tensor<4xf32> {
  // CHECK: %[[VH0:.*]] = "tf.VarHandleOp"()
  // CHECK: %[[VH1:.*]] = "tf.VarHandleOp"()
  // CHECK: %[[READ0:.*]] = "tf.ReadVariableOp"(%[[VH0]])
  // CHECK: %[[READ1:.*]] = "tf.ReadVariableOp"(%[[VH1]])
  // CHECK: %[[CLUSTER:.*]]:2 = "tf_device.cluster"()
  // CHECK: %[[IF:.*]]:2 = "tf.IfRegion"(%[[ARG0]])
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  %1 = "tf.VarHandleOp"() {container = "c", shared_name = "v2"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  %2 = "tf_device.cluster"() ( {
    %3:2 = "tf.IfRegion"(%arg0) ({
          // CHECK-NEXT: %[[CONST:.*]] = "tf.Const"()
          // CHECK-NEXT: "tf.Yield"(%[[CONST]], %[[CONST]])
          %constant = "tf.Const"() {value = dense<0.0> : tensor<4xf32>} : () -> tensor<4xf32>
          "tf.AssignVariableOp"(%0, %constant) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
          "tf.Yield"(%0, %constant) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
      }, {
          // CHECK: %[[IF1:.*]] = "tf.IfRegion"
          // CHECK:  "tf.Yield"(%[[READ1]])
          // CHECK:  "tf.Yield"(%[[READ0]])
          // CHECK: "tf.Yield"(%[[IF1]], %[[IF1]])
          %id = "tf.Identity"(%1) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<*x!tf.resource<tensor<4xf32>>>
          %read = "tf.IfRegion"(%arg1) ({
            %read_then = "tf.ReadVariableOp"(%id) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
            "tf.Yield"(%read_then) : (tensor<4xf32>) -> ()
          }, {
            %read_else = "tf.ReadVariableOp"(%0) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
            "tf.Yield"(%read_else) : (tensor<4xf32>) -> ()
          }) {is_stateless = false} : (tensor<i1>) -> tensor<4xf32>
          "tf.AssignVariableOp"(%0, %read) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
          "tf.Yield"(%0, %read) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
      }) {is_stateless = false} : (tensor<i1>) -> (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>)
    // CHECK: %[[ADD:.*]] = "tf.AddV2"(%[[IF]]#1, %[[IF]]#0)
    // CHECK-NEXT: tf_device.return %[[ADD]], %[[IF]]#1
    %4 = "tf.ReadVariableOp"(%3#0) : (tensor<*x!tf.resource<tensor<4xf32>>>) -> tensor<4xf32>
    %5 = "tf.AddV2"(%4, %3#1) : (tensor<4xf32>, tensor<4xf32>) -> tensor<4xf32>
    tf_device.return %5 : tensor<4xf32>
  }) {cluster_attr = "cluster_attr"} : () -> tensor<4xf32>
  // CHECK: {cluster_attr = "cluster_attr"} : () -> (tensor<4xf32>, tensor<4xf32>)
  // CHECK: "tf.AssignVariableOp"(%[[VH0]], %[[CLUSTER]]#1)
  // CHECK: return %[[CLUSTER]]#0
  return %2 : tensor<4xf32>
}

// -----

// IfRegion with store in just one branch

// CHECK: func @if_region_with_store_in_then(%[[ARG0:.*]]: tensor<i1>)
func @if_region_with_store_in_then(%arg0: tensor<i1>) {
  // CHECK: %[[VH:.*]] = "tf.VarHandleOp"()
  // CHECK: %[[READ:.*]] = "tf.ReadVariableOp"(%[[VH]])
  // CHECK: %[[CLUSTER:.*]] = "tf_device.cluster"()
  // CHECK: %[[IF:.*]] = "tf.IfRegion"(%[[ARG0]])
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  "tf_device.cluster"() ({
    "tf.IfRegion"(%arg0) ({
       // CHECK: %[[CONST:.*]] = "tf.Const"() {value = dense<0.000000e+00>
       // CHECK: "tf.Yield"(%[[CONST]])
       %constant = "tf.Const"() {value = dense<0.0> : tensor<4xf32>} : () -> tensor<4xf32>
       "tf.AssignVariableOp"(%0, %constant) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
       "tf.Yield"() : () -> ()
      }, {
       // CHECK: "tf.Yield"(%[[READ]])
       "tf.Yield"() : () -> ()
      }) { is_stateless = true} : (tensor<i1>) -> ()
    tf_device.return
  }) { cluster_attr = "cluster_attr" } : () -> ()
  // CHECK: tf_device.return %[[IF]]
  // CHECK: "tf.AssignVariableOp"(%[[VH0]], %[[CLUSTER]])
  return
}

// -----

// IfRegion with store in both branches

// CHECK: func @if_region_with_store_in_both(%[[ARG0:.*]]: tensor<i1>)
func @if_region_with_store_in_both(%arg0: tensor<i1>) {
  // CHECK: %[[VH:.*]] = "tf.VarHandleOp"()
  // CHECK: %[[CLUSTER:.*]] = "tf_device.cluster"()
  // CHECK: %[[IF:.*]] = "tf.IfRegion"(%[[ARG0]])
  %0 = "tf.VarHandleOp"() {container = "c", shared_name = "v"} : () -> tensor<*x!tf.resource<tensor<4xf32>>>
  "tf_device.cluster"() ({
    "tf.IfRegion"(%arg0) ({
       // CHECK: %[[CONST:.*]] = "tf.Const"() {value = dense<0.000000e+00>
       // CHECK: "tf.Yield"(%[[CONST]])
       %constant = "tf.Const"() {value = dense<0.0> : tensor<4xf32>} : () -> tensor<4xf32>
       "tf.AssignVariableOp"(%0, %constant) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
       "tf.Yield"() : () -> ()
      }, {
       // CHECK: %[[CONST:.*]] = "tf.Const"() {value = dense<1.000000e+00>
       // CHECK: "tf.Yield"(%[[CONST]])
       %constant = "tf.Const"() {value = dense<1.0> : tensor<4xf32>} : () -> tensor<4xf32>
       "tf.AssignVariableOp"(%0, %constant) : (tensor<*x!tf.resource<tensor<4xf32>>>, tensor<4xf32>) -> ()
       "tf.Yield"() : () -> ()
      }) { is_stateless = true} : (tensor<i1>) -> ()
    tf_device.return
  }) { cluster_attr = "cluster_attr" } : () -> ()
  // CHECK: tf_device.return %[[IF]]
  // CHECK: "tf.AssignVariableOp"(%[[VH0]], %[[CLUSTER]])
  return
}




