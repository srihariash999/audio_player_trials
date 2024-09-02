import 'package:audio_player_trials/audio_bloc.dart';
import 'package:audio_player_trials/common.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

Future<void> main() async {
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.zepplaud.podboi',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.speech());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AudioBloc>(
              create: (BuildContext context) => AudioBloc(),
            ),
          ],
          child: const MyHomePage(title: 'Flutter Demo Home Page'),
        ));
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<AudioBloc, AudioState>(builder: (context, state) {
          if (state is AudioStateInitial) {
            return SizedBox(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Not playing"),
                    ElevatedButton(
                        onPressed: () {
                          context.read<AudioBloc>().add(PlayEpisodeEvent());
                        },
                        child: const Text("Play")),
                  ],
                ),
              ),
            );
          }

          if (state is AudioStateLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is AudioStatePlaying) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: StreamBuilder<SequenceState?>(
                    stream: state.player.sequenceStateStream,
                    builder: (context, snapshot) {
                      final state = snapshot.data;
                      if (state?.sequence.isEmpty ?? true) {
                        return const SizedBox();
                      }
                      final metadata = state!.currentSource!.tag as MediaItem;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Center(
                                  child: Image.network(
                                      metadata.artUri.toString())),
                            ),
                          ),
                          Text(metadata.album!,
                              style: Theme.of(context).textTheme.titleLarge),
                          Text(metadata.title),
                        ],
                      );
                    },
                  ),
                ),
                ControlButtons(state.player),
                StreamBuilder<PositionData>(
                  stream: state.positionDataStream,
                  builder: (context, snapshot) {
                    final positionData = snapshot.data;
                    return SeekBar(
                      duration: positionData?.duration ?? Duration.zero,
                      position: positionData?.position ?? Duration.zero,
                      bufferedPosition:
                          positionData?.bufferedPosition ?? Duration.zero,
                      onChangeEnd: (newPosition) {
                        state.player.seek(newPosition);
                      },
                    );
                  },
                ),
                const SizedBox(height: 8.0),
                Row(
                  children: [
                    StreamBuilder<LoopMode>(
                      stream: state.player.loopModeStream,
                      builder: (context, snapshot) {
                        final loopMode = snapshot.data ?? LoopMode.off;
                        const icons = [
                          Icon(Icons.repeat, color: Colors.grey),
                          Icon(Icons.repeat, color: Colors.orange),
                          Icon(Icons.repeat_one, color: Colors.orange),
                        ];
                        const cycleModes = [
                          LoopMode.off,
                          LoopMode.all,
                          LoopMode.one,
                        ];
                        final index = cycleModes.indexOf(loopMode);
                        return IconButton(
                          icon: icons[index],
                          onPressed: () {
                            state.player.setLoopMode(cycleModes[
                                (cycleModes.indexOf(loopMode) + 1) %
                                    cycleModes.length]);
                          },
                        );
                      },
                    ),
                    Expanded(
                      child: Text(
                        "Playlist",
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    StreamBuilder<bool>(
                      stream: state.player.shuffleModeEnabledStream,
                      builder: (context, snapshot) {
                        final shuffleModeEnabled = snapshot.data ?? false;
                        return IconButton(
                          icon: shuffleModeEnabled
                              ? const Icon(Icons.shuffle, color: Colors.orange)
                              : const Icon(Icons.shuffle, color: Colors.grey),
                          onPressed: () async {
                            final enable = !shuffleModeEnabled;
                            if (enable) {
                              await state.player.shuffle();
                            }
                            await state.player.setShuffleModeEnabled(enable);
                          },
                        );
                      },
                    ),
                  ],
                ),
                SizedBox(
                  height: 240.0,
                  child: StreamBuilder<SequenceState?>(
                    stream: state.player.sequenceStateStream,
                    builder: (context, snapshot) {
                      final streamState = snapshot.data;
                      final sequence = streamState?.sequence ?? [];
                      return ReorderableListView(
                        onReorder: (int oldIndex, int newIndex) {
                          context.read<AudioBloc>().add(
                                ReorderItemInPlaylistEvent(
                                  oldIndex: oldIndex,
                                  newIndex: newIndex,
                                ),
                              );
                        },
                        children: [
                          for (var i = 0; i < sequence.length; i++)
                            Dismissible(
                              key: ValueKey(sequence[i]),
                              background: Container(
                                color: Colors.redAccent,
                                alignment: Alignment.centerRight,
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 8.0),
                                  child:
                                      Icon(Icons.delete, color: Colors.white),
                                ),
                              ),
                              onDismissed: (dismissDirection) {
                                context
                                    .read<AudioBloc>()
                                    .add(RemoveItemFromPlaylistEvent(index: i));
                              },
                              child: Material(
                                color: i == streamState!.currentIndex
                                    ? Colors.grey.shade300
                                    : null,
                                child: ListTile(
                                  title: Text(sequence[i].tag.title as String),
                                  onTap: () {
                                    state.player.seek(Duration.zero, index: i);
                                  },
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            );
          }

          return SizedBox(
            child: Text("state is unkown: $state"),
          );
        }),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          var state = context.read<AudioBloc>().state;
          if ((state is! AudioStatePlaying)) return;

          print(" nextMediaId ${state.nextMediaId}");
          print(" addedCount ${state.addedCount}");

          context.read<AudioBloc>().add(AddItemToPlaylistEvent(
                audioSource: AudioSource.uri(
                  Uri.parse(
                      "https://raw.githubusercontent.com/rafaelreis-hotmart/Audio-Sample-files/master/sample.mp3"),
                  tag: MediaItem(
                    id: '${state.nextMediaId + 1}',
                    album: "Random ass music",
                    title: "Random music ${state.nextMediaId + 1}",
                    artUri: Uri.parse(
                        "https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg"),
                  ),
                ),
              ));
        },
      ),
    );
  }
}

class ControlButtons extends StatelessWidget {
  final AudioPlayer player;

  const ControlButtons(this.player, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.volume_up),
          onPressed: () {
            showSliderDialog(
              context: context,
              title: "Adjust volume",
              divisions: 10,
              min: 0.0,
              max: 1.0,
              stream: player.volumeStream,
              onChanged: player.setVolume,
            );
          },
        ),
        StreamBuilder<SequenceState?>(
          stream: player.sequenceStateStream,
          builder: (context, snapshot) => IconButton(
            icon: const Icon(Icons.skip_previous),
            onPressed: player.hasPrevious ? player.seekToPrevious : null,
          ),
        ),
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final processingState = playerState?.processingState;
            final playing = playerState?.playing;
            if (processingState == ProcessingState.loading ||
                processingState == ProcessingState.buffering) {
              return Container(
                margin: const EdgeInsets.all(8.0),
                width: 64.0,
                height: 64.0,
                child: const CircularProgressIndicator(),
              );
            } else if (playing != true) {
              return IconButton(
                icon: const Icon(Icons.play_arrow),
                iconSize: 64.0,
                onPressed: player.play,
              );
            } else if (processingState != ProcessingState.completed) {
              return IconButton(
                icon: const Icon(Icons.pause),
                iconSize: 64.0,
                onPressed: player.pause,
              );
            } else {
              return IconButton(
                icon: const Icon(Icons.replay),
                iconSize: 64.0,
                onPressed: () => player.seek(Duration.zero,
                    index: player.effectiveIndices!.first),
              );
            }
          },
        ),
        StreamBuilder<SequenceState?>(
          stream: player.sequenceStateStream,
          builder: (context, snapshot) => IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: player.hasNext ? player.seekToNext : null,
          ),
        ),
        StreamBuilder<double>(
          stream: player.speedStream,
          builder: (context, snapshot) => IconButton(
            icon: Text("${snapshot.data?.toStringAsFixed(1)}x",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              showSliderDialog(
                context: context,
                title: "Adjust speed",
                divisions: 10,
                min: 0.5,
                max: 1.5,
                stream: player.speedStream,
                onChanged: player.setSpeed,
              );
            },
          ),
        ),
      ],
    );
  }
}
