import 'dart:io';

import 'package:kyber_launcher/core/services/instance_manager.dart';

void _expectEq(Object? actual, Object? expected, String label) {
  if (actual != expected) {
    throw StateError('$label: expected $expected, got $actual');
  }
}

void main() {
  _expectEq(
    InstanceManager.parsePlayerNameArg(['--name', 'player1']),
    'player1',
    '--name space arg',
  );
  _expectEq(
    InstanceManager.parsePlayerNameArg(['--name=player1']),
    'player1',
    '--name= arg',
  );
  _expectEq(
    InstanceManager.parsePlayerNameArg(['-n', '  player2  ']),
    'player2',
    '-n trimmed arg',
  );
  _expectEq(
    InstanceManager.parsePlayerNameArg(['-n=player3']),
    'player3',
    '-n= arg',
  );
  _expectEq(
    InstanceManager.parsePlayerNameArg(['--other', '--name']),
    null,
    'missing value',
  );
  _expectEq(
    InstanceManager.parsePlayerNameArg(['--name', r'bad\name']),
    null,
    'backslash rejected',
  );
  _expectEq(
    InstanceManager.parsePlayerNameArg(['--name', 'a-name-way-too-long']),
    null,
    'over 16 chars rejected',
  );

  _expectEq(
    InstanceManager.resolveInitialNickname(
      overrideName: 'player1',
      savedName: 'SavedNick',
      suffix: ' 2',
    ),
    'player1',
    'override beats saved',
  );
  _expectEq(
    InstanceManager.resolveInitialNickname(
      savedName: 'SavedNick',
      suffix: ' 2',
    ),
    'SavedNick',
    'saved beats default',
  );
  _expectEq(
    InstanceManager.resolveInitialNickname(suffix: ''),
    'Jedha',
    'default instance 0',
  );
  _expectEq(
    InstanceManager.resolveInitialNickname(suffix: ' 2'),
    'Jedha 2',
    'default instance 1',
  );
  stdout.writeln('ALL_INSTANCE_MANAGER_TESTS_OK');
}
