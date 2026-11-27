import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

import 'verdict_style.dart';

/// Lit une vidéo choisie par l'agent, sans l'envoyer sur le réseau :
/// le contenu est placé dans un `Blob` du navigateur, lu par une adresse
/// temporaire `blob:` libérée à la fermeture.
class VideoDialog extends StatefulWidget {
  const VideoDialog({
    super.key,
    required this.fileName,
    required this.loadBytes,
  });

  final String fileName;
  final Future<List<int>> Function() loadBytes;

  @override
  State<VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<VideoDialog> {
  VideoPlayerController? _controller;
  String? _blobUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.loadBytes();
      final blob = web.Blob(
        [Uint8List.fromList(bytes).toJS].toJS,
        web.BlobPropertyBag(type: 'video/mp4'),
      );
      final url = web.URL.createObjectURL(blob);
      _blobUrl = url;

      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.play();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = 'Lecture impossible : $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    final url = _blobUrl;
    if (url != null) web.URL.revokeObjectURL(url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AlertDialog(
      title: Text(shortSegmentName(widget.fileName)),
      content: SizedBox(
        width: 720,
        child: _error != null
            ? Text(_error!)
            : controller == null
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                  VideoProgressIndicator(controller, allowScrubbing: true),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => IconButton(
                      icon: Icon(
                        value.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                      onPressed: value.isPlaying
                          ? controller.pause
                          : controller.play,
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
