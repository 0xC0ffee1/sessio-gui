export PATH="$PATH:$HOME/.pub-cache/bin"
protoc --dart_out=grpc:lib/src/generated -Iproto proto/client_ipc.proto
