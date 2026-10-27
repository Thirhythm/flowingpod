import 'package:flowingpod/core/models/media_track.dart';
import 'package:flowingpod/data/services/player_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// [bvid] doubles as the label so expectations read like the queue itself.
MediaTrack _track(String bvid, {int page = 1}) => MediaTrack(
  bvid: bvid,
  aid: 1,
  cid: 1,
  title: bvid,
  artist: 'UP主',
  cover: '',
  page: page,
);

List<String> _labels(List<MediaTrack> queue) => [
  for (final track in queue) track.bvid,
];

void main() {
  group('planPlayNext', () {
    test('inserts an unknown track directly after the current entry', () {
      final plan = planPlayNext(
        [_track('A'), _track('B'), _track('C')],
        0,
        _track('D'),
      );

      expect(_labels(plan!.queue), ['A', 'D', 'B', 'C']);
      expect(plan.currentIndex, 0);
    });

    test(
      'moves an entry that comes later in the queue instead of adding it',
      () {
        final plan = planPlayNext(
          [_track('A'), _track('B'), _track('C')],
          0,
          _track('C'),
        );

        expect(_labels(plan!.queue), ['A', 'C', 'B']);
        expect(plan.queue, hasLength(3));
        expect(plan.currentIndex, 0);
      },
    );

    test('moves an entry from before the current one and keeps it playing', () {
      final plan = planPlayNext(
        [_track('A'), _track('B'), _track('C')],
        2,
        _track('A'),
      );

      expect(_labels(plan!.queue), ['B', 'C', 'A']);
      // The current entry is still C, now one slot earlier.
      expect(plan.queue[plan.currentIndex].bvid, 'C');
    });

    test('leaves a queue that already plays the entry next untouched', () {
      final plan = planPlayNext([_track('A'), _track('B')], 0, _track('B'));

      expect(_labels(plan!.queue), ['A', 'B']);
      expect(plan.currentIndex, 0);
    });

    test('the track playing right now cannot be queued behind itself', () {
      expect(planPlayNext([_track('A')], 0, _track('A')), isNull);
      expect(
        planPlayNext([_track('A'), _track('B')], 0, _track('A')),
        isNull,
        reason: 'moving the current entry would change what is playing',
      );
    });

    test('matches the same part of a video coming from another list', () {
      // A search result carries the video only; the queue holds the resolved
      // part it was expanded into.
      const resolved = MediaTrack(
        bvid: 'BV1',
        aid: 1,
        cid: 99,
        title: 'BV1',
        artist: 'UP主',
        cover: '',
      );
      final plan = planPlayNext(
        [resolved, _track('B'), _track('C')],
        1,
        MediaTrack(
          bvid: 'BV1',
          aid: 1,
          cid: 0,
          title: 'BV1',
          artist: 'UP主',
          cover: '',
        ),
      );

      expect(_labels(plan!.queue), ['B', 'BV1', 'C']);
      expect(plan.queue, hasLength(3));
      expect(plan.currentIndex, 0);
    });

    test('another part of the same video is a separate entry', () {
      final plan = planPlayNext(
        [_track('BV1'), _track('B')],
        0,
        _track('BV1', page: 2),
      );

      expect(_labels(plan!.queue), ['BV1', 'BV1', 'B']);
      expect(plan.queue[1].page, 2);
    });
  });
}
