import 'package:audio_player_trials/common.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:rxdart/rxdart.dart';

//! ---------------- EVENTS ------------------

@immutable
abstract class AudioEvent {}

class PlayEpisodeEvent extends AudioEvent {}

class ReorderItemInPlaylistEvent extends AudioEvent {
  final int oldIndex;
  final int newIndex;
  ReorderItemInPlaylistEvent({required this.oldIndex, required this.newIndex});
}

class AddItemToPlaylistEvent extends AudioEvent {
  final AudioSource audioSource;
  AddItemToPlaylistEvent({required this.audioSource});
}

class RemoveItemFromPlaylistEvent extends AudioEvent {
  final int index;
  RemoveItemFromPlaylistEvent({required this.index});
}

//! ---------------- STATES ------------------
@immutable
abstract class AudioState {
  final Stream<PositionData>? positionDataStream;

  const AudioState({required this.positionDataStream});
}

class AudioStateInitial extends AudioState {
  const AudioStateInitial() : super(positionDataStream: null);
}

class AudioStateLoading extends AudioState {
  const AudioStateLoading() : super(positionDataStream: null);
}

class AudioStatePlaying extends AudioState {
  final Stream<PositionData> stream;
  final AudioPlayer player;
  final int nextMediaId;
  final int addedCount;
  const AudioStatePlaying({
    required this.stream,
    required this.player,
    required this.nextMediaId,
    required this.addedCount,
  }) : super(positionDataStream: stream);
}

//! ---------------- BLoC ------------------

class AudioBloc extends Bloc<AudioEvent, AudioState> {
  AudioPlayer? _player;

  final _playlist = ConcatenatingAudioSource(children: []);

  static int _nextMediaId = 0;

  int _addedCount = 0;

  Stream<PositionData>? get _positionDataStream =>
      _player?.positionStream != null &&
              _player?.bufferedPositionStream != null &&
              _player?.durationStream != null
          ? Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
              _player!.positionStream,
              _player!.bufferedPositionStream,
              _player!.durationStream,
              (position, bufferedPosition, duration) => PositionData(
                  position, bufferedPosition, duration ?? Duration.zero))
          : null;

  AudioBloc() : super(const AudioStateInitial()) {
    // Play item handling
    on<PlayEpisodeEvent>((event, emit) async {
      emit(const AudioStateLoading());

      _player ??= AudioPlayer();

      _playlist.add(
        AudioSource.uri(
          Uri.parse(
              "https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3"),
          tag: MediaItem(
            id: '${_nextMediaId++}',
            album: "Science Friday",
            title: "A Salute To Head-Scratching Science",
            artUri: Uri.parse(
                "https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg"),
          ),
        ),
      );

      // Listen to errors during playback.
      _player!.playbackEventStream.listen((event) {},
          onError: (Object e, StackTrace stackTrace) {
        print('A stream error occurred: $e');
      });
      try {
        await _player!.setAudioSource(_playlist);
      } catch (e, stackTrace) {
        // Catch load errors: 404, invalid url ...
        print("Error loading playlist: $e");
        print(stackTrace);
      }

      _player!.play();

      emit(
        AudioStatePlaying(
          stream: _positionDataStream!,
          player: _player!,
          nextMediaId: _nextMediaId,
          addedCount: _addedCount,
        ),
      );
    });

    // Reorder playlist item handling
    on<ReorderItemInPlaylistEvent>((event, emit) async {
      var oldIndex = event.oldIndex;
      var newIndex = event.newIndex;

      if (oldIndex < newIndex) newIndex--;
      _playlist.move(oldIndex, newIndex);
    });

    // Add item to playlist handling
    on<AddItemToPlaylistEvent>((event, emit) async {
      _playlist.add(event.audioSource);
      _addedCount++;
      _nextMediaId++;
      emit(
        AudioStatePlaying(
          stream: _positionDataStream!,
          player: _player!,
          nextMediaId: _nextMediaId,
          addedCount: _addedCount,
        ),
      );
    });

    // Remove item from playlist handling
    on<RemoveItemFromPlaylistEvent>((event, emit) async {
      _playlist.removeAt(event.index);
    });
  }
}
