{ lib
, buildPythonPackage
, fetchPypi
, pytestCheckHook
, grpc_google_iam_v1
, google-api-core
, libcst
, mock
, proto-plus
, pytest-asyncio
}:

buildPythonPackage rec {
  pname = "google-cloud-kms";
  version = "2.5.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-OuvpnIJeG+O+2Teopq8FYJOHIyi1V3RdlmJEq/fFSxM=";
  };

  propagatedBuildInputs = [ grpc_google_iam_v1 google-api-core libcst proto-plus ];

  checkInputs = [ mock pytestCheckHook pytest-asyncio ];

  # Disable tests that need credentials
  disabledTests = [ "test_list_global_key_rings" ];

  pythonImportsCheck = [
    "google.cloud.kms"
    "google.cloud.kms_v1"
  ];

  meta = with lib; {
    description = "Cloud Key Management Service (KMS) API API client library";
    homepage = "https://github.com/googleapis/python-kms";
    license = licenses.asl20;
    maintainers = with maintainers; [ SuperSandro2000 ];
  };
}
