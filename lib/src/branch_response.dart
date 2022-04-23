part of flutter_branch_sdk_objects;

class BranchResponse<T> {
  bool success = true;
  T result;
  String errorCode = '';
  String errorMessage = '';

  BranchResponse.success({this.result}) {
    this.success = true;
  }
  BranchResponse.error({this.errorCode, this.errorMessage}) {
    this.success = false;
  }

  @override
  String toString() {
    return ('success: $success, errorCode: $errorCode, errorMessage: $errorMessage}');
  }
}
