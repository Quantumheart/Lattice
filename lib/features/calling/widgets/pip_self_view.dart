import 'package:flutter/material.dart';
import 'package:lattice/features/calling/models/call_participant.dart';
import 'package:lattice/features/calling/widgets/participant_tile.dart';

// coverage:ignore-start

class PipSelfView extends StatefulWidget {
  const PipSelfView({required this.participant, super.key});

  final CallParticipant participant;

  static const double width = 120;
  static const double height = 160;
  static const double _margin = 16;

  @override
  State<PipSelfView> createState() => _PipSelfViewState();
}

class _PipSelfViewState extends State<PipSelfView> {
  Offset? _position;
  BoxConstraints? _lastConstraints;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _lastConstraints = constraints;
          final maxX = constraints.maxWidth - PipSelfView.width - PipSelfView._margin;
          final maxY = constraints.maxHeight - PipSelfView.height - PipSelfView._margin;
          final x = (_position?.dx ?? maxX).clamp(PipSelfView._margin, maxX);
          final y = (_position?.dy ?? maxY).clamp(PipSelfView._margin, maxY);

          return Stack(
            children: [
              Positioned(
                left: x,
                top: y,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _position = Offset(
                        ((_position?.dx ?? maxX) + details.delta.dx)
                            .clamp(PipSelfView._margin, maxX),
                        ((_position?.dy ?? maxY) + details.delta.dy)
                            .clamp(PipSelfView._margin, maxY),
                      );
                    });
                  },
                  onPanEnd: (_) => _snapToCorner(constraints),
                  onPanCancel: () {
                    if (_lastConstraints != null) _snapToCorner(_lastConstraints!);
                  },
                  child: SizedBox(
                    width: PipSelfView.width,
                    height: PipSelfView.height,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: ParticipantTile(participant: widget.participant),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _snapToCorner(BoxConstraints constraints) {
    final maxX = constraints.maxWidth - PipSelfView.width - PipSelfView._margin;
    final maxY = constraints.maxHeight - PipSelfView.height - PipSelfView._margin;
    final cx = _position?.dx ?? maxX;
    final cy = _position?.dy ?? maxY;

    final midX = constraints.maxWidth / 2;
    final midY = constraints.maxHeight / 2;

    setState(() {
      _position = Offset(
        cx < midX ? PipSelfView._margin : maxX,
        cy < midY ? PipSelfView._margin : maxY,
      );
    });
  }
}
// coverage:ignore-end
