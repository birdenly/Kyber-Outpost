// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';

class EventCubit extends Cubit<EventState> {
  EventCubit() : super(EventsLoading()) {
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    emit(EventsLoaded(posts: const <Post>[]));
  }
}

abstract class EventState {}

class EventsError extends EventState {
  final String error;

  EventsError({required this.error});
}

class EventsLoading extends EventState {}

class EventsLoaded extends EventState {
  final List<Post> posts;

  EventsLoaded({required this.posts});
}
