import 'package:flutter_test/flutter_test.dart';
import 'package:siap_app/core/utils/nis_siswa.dart';

void main() {
  test('nisNip diutamakan (diisi impor CSV)', () {
    expect(nisDariDataSiswa({'nisNip': '12345', 'email': '12345', 'nis': '999'}), '12345');
  });

  test('field nis dipakai bila nisNip kosong', () {
    expect(nisDariDataSiswa({'nisNip': '  ', 'nis': '777'}), '777');
  });

  test('email tanpa @ dianggap NIS (data lama), email asli tidak', () {
    expect(nisDariDataSiswa({'email': '555'}), '555');
    expect(nisDariDataSiswa({'email': 'siswa@sekolah.sch.id'}), '');
  });

  test('angka dan spasi dirapikan menjadi teks', () {
    expect(nisDariDataSiswa({'nisNip': 12345}), '12345');
    expect(nisDariDataSiswa({'nis': ' 0012 '}), '0012');
  });

  test('tanpa NIS menghasilkan string kosong', () {
    expect(nisDariDataSiswa({'name': 'Budi'}), '');
  });
}
