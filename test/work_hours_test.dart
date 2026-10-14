import 'package:flutter_test/flutter_test.dart';

import 'package:pensiune_app/main.dart';

void main() {
  test('orele pe zile se citesc înapoi identic', () {
    const hours = {
      5: DayHours(960, 720),
      1: DayHours(840, 660),
    };
    expect(encodeWorkHours(hours), '1:840-660,5:960-720');
    expect(parseWorkHours(encodeWorkHours(hours)), hours);
  });

  test('nicio zi cu check-in → text gol → nicio zi', () {
    expect(encodeWorkHours({}), '');
    expect(parseWorkHours(''), isEmpty);
  });

  test('intrările invalide sunt sărite', () {
    expect(
      parseWorkHours('0:840-660,8:840-660,x,2:840-660,3:1440-660,4:840-1440'),
      {2: const DayHours(840, 660)},
    );
  });

  test('orele propuse: ziua aleasă, altfel prima zi cu check-in', () {
    const s = BookingSettingsData(
      enabled: true,
      workHours: {5: DayHours(960, 720), 2: DayHours(840, 660)},
    );
    expect(s.hoursFor(5), const DayHours(960, 720));
    expect(s.hoursFor(1), const DayHours(840, 660));
    expect(s.hoursFor(null), const DayHours(840, 660));
  });
}
