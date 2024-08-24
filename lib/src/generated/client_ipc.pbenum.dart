//
//  Generated code. Do not modify.
//  source: client_ipc.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class NatFilterType extends $pb.ProtobufEnum {
  static const NatFilterType ENDPOINT_INDEPENDENT = NatFilterType._(0, _omitEnumNames ? '' : 'ENDPOINT_INDEPENDENT');
  static const NatFilterType ADDRESS_DEPENDENT = NatFilterType._(1, _omitEnumNames ? '' : 'ADDRESS_DEPENDENT');
  static const NatFilterType ADDRESS_AND_PORT_DEPENDENT = NatFilterType._(2, _omitEnumNames ? '' : 'ADDRESS_AND_PORT_DEPENDENT');
  static const NatFilterType UNKNOWN = NatFilterType._(3, _omitEnumNames ? '' : 'UNKNOWN');

  static const $core.List<NatFilterType> values = <NatFilterType> [
    ENDPOINT_INDEPENDENT,
    ADDRESS_DEPENDENT,
    ADDRESS_AND_PORT_DEPENDENT,
    UNKNOWN,
  ];

  static final $core.Map<$core.int, NatFilterType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static NatFilterType? valueOf($core.int value) => _byValue[value];

  const NatFilterType._($core.int v, $core.String n) : super(v, n);
}

class ClientEvent_StreamType extends $pb.ProtobufEnum {
  static const ClientEvent_StreamType TRANSPORT = ClientEvent_StreamType._(0, _omitEnumNames ? '' : 'TRANSPORT');
  static const ClientEvent_StreamType SESSION = ClientEvent_StreamType._(1, _omitEnumNames ? '' : 'SESSION');
  static const ClientEvent_StreamType CHANNEL = ClientEvent_StreamType._(2, _omitEnumNames ? '' : 'CHANNEL');

  static const $core.List<ClientEvent_StreamType> values = <ClientEvent_StreamType> [
    TRANSPORT,
    SESSION,
    CHANNEL,
  ];

  static final $core.Map<$core.int, ClientEvent_StreamType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ClientEvent_StreamType? valueOf($core.int value) => _byValue[value];

  const ClientEvent_StreamType._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
