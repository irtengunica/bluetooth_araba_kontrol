# Bluetooth Kontrollü Araba - Flutter Uygulaması

Bu proje, Flutter ile geliştirilmiş bir mobil uygulama aracılığıyla Bluetooth (HC-05/HC-06 gibi Klasik Bluetooth modülleri) üzerinden bir oyuncak arabanın veya robotun kontrol edilmesini sağlar. Kullanıcı dostu bir arayüz üzerinden araca ileri, geri, sağa, sola dönme ve durma gibi komutlar gönderilebilir.

![Uygulama Ekran Görüntüsü](placeholder_screenshot.png)
*Lütfen buraya uygulamanızın bir ekran görüntüsünü ekleyin. `placeholder_screenshot.png` adında bir dosya oluşturup reponuza yükleyin veya doğrudan bir URL kullanın.*

## 🚗 Özellikler

*   **Bluetooth Bağlantısı:** Yakındaki Bluetooth cihazlarını tarama ve seçilen cihaza (örn: HC-06) bağlanma.
*   **Araç Kontrolü:**
    *   İleri Git (F)
    *   Geri Git (B)
    *   Sola Dön (L)
    *   Sağa Dön (R)
    *   Dur (S)
    *   Tam Sola Dön (T)
    *   Tam Sağa Dön (D)
    *   İleri Sol (X)
    *   İleri Sağ (M)
    *   Geri Sol (N)
    *   Geri Sağ (Y)
*   **Basılı Tutarak Kontrol:** Yön butonlarına basılı tutulduğu sürece ilgili hareket komutu gönderilir, parmak çekildiğinde araç durur ('S' komutu gönderilir).
*   **Görsel Geri Bildirim:** Butonlara basıldığında renk değişimi.
*   **Hız Kontrolü:** Ayarlanabilir hız seviyesi için bir kaydırıcı (bu özelliğin araç tarafında desteklenmesi gerekir).
*   **Runtime İzin Yönetimi:** Android için gerekli Bluetooth ve konum izinlerini çalışma zamanında ister.

## 🛠️ Kullanılan Teknolojiler

*   **Flutter:** Google tarafından geliştirilen, tek bir kod tabanından mobil, web ve masaüstü uygulamaları oluşturmak için kullanılan UI toolkit.
*   **Dart:** Flutter uygulamalarının programlama dili.
*   **`flutter_bluetooth_serial`:** Klasik Bluetooth (SPP) iletişimi için Flutter eklentisi.
*   **`permission_handler`:** Çalışma zamanı izinlerini yönetmek için Flutter eklentisi.

## ⚙️ Kurulum ve Kullanım

### Ön Gereksinimler

*   Flutter SDK'nın kurulu olması. (Kurulum için: [Flutter Resmi Sitesi](https://flutter.dev/docs/get-started/install))
*   Android Studio veya VS Code gibi bir Flutter IDE'si.
*   Bluetooth kontrollü bir araba veya robot (örn: HC-05/HC-06 modülü ve Arduino tabanlı). **Aracınızın mikrodenetleyicisinin bu uygulamadan gönderilen karakter komutlarını ('F', 'B', 'S' vb.) anlayacak şekilde programlanmış olması gerekir.**

### Projeyi Çalıştırma

1.  **Repoyu Klonlayın:**
    ```bash
    git clone [https://github.com/kullaniciadiniz/proje-adiniz.git](https://github.com/irtengunica/bluetooth_araba_kontrol.git)
    cd bluetooth_araba_kontrol
    ```
    *`kullaniciadiniz/proje-adiniz` kısmını kendi GitHub kullanıcı adınız ve repo adınızla değiştirin.*

2.  **Bağımlılıkları Yükleyin:**
    Proje ana dizininde aşağıdaki komutu çalıştırın:
    ```bash
    flutter pub get
    ```

3.  **Uygulamayı Çalıştırın:**
    Bir Android cihazı bilgisayarınıza bağlayın veya bir Android emülatörü başlatın. Ardından aşağıdaki komutu çalıştırın:
    ```bash
    flutter run
    ```

### Android İzinleri

Uygulama, Bluetooth taraması ve bağlantısı için aşağıdaki izinleri isteyecektir:
*   **Konum İzni:** Yakındaki Bluetooth cihazlarını bulmak için gereklidir.
*   **Bluetooth İzinleri (Android 12+):** `BLUETOOTH_SCAN` ve `BLUETOOTH_CONNECT` izinleri.

Lütfen uygulama ilk açıldığında veya ilgili özellikler kullanılmaya çalışıldığında çıkan izin isteklerini kabul edin. Ayrıca, bazı Android cihazlarında **Konum Servisleri'nin (GPS) sistem ayarlarından açık olması** gerekebilir.

## 🔌 Araç Tarafı (Arduino Örneği - HC-06 ile)

Bu Flutter uygulaması, seri port üzerinden tek karakterlik komutlar gönderir. İşte bu komutları alıp basit bir L298N motor sürücüsü ile iki motoru kontrol eden temel bir Arduino kodu örneği:

```cpp
// Arduino Kodu Örneği (Bluetooth_Araba_Kontrol_Arduino.ino)

#include <SoftwareSerial.h> // Eğer donanımsal seri port meşgulse veya farklı pinler kullanılacaksa.
// Eğer Arduino'nun donanımsal RX/TX pinlerini (0 ve 1) kullanıyorsanız SoftwareSerial'a gerek yok.
// Ancak bu pinler USB iletişimi için de kullanıldığından dikkatli olun.

// Motor A (Sol Motor) pinleri
int enA = 9; // PWM pini (Hız kontrolü için)
int in1 = 8;
int in2 = 7;

// Motor B (Sağ Motor) pinleri
int enB = 3; // PWM pini
int in3 = 5;
int in4 = 4;

char command; // Bluetooth'tan gelen komutu tutacak değişken

void setup() {
  Serial.begin(9600); // HC-06 modülünün baud rate'i ile eşleşmeli (genellikle 9600)
  pinMode(enA, OUTPUT);
  pinMode(in1, OUTPUT);
  pinMode(in2, OUTPUT);
  pinMode(enB, OUTPUT);
  pinMode(in3, OUTPUT);
  pinMode(in4, OUTPUT);

  // Başlangıçta motorları durdur
  stopMotors();
  Serial.println("Araba Hazır. Komut Bekleniyor...");
}

void loop() {
  if (Serial.available() > 0) {
    command = Serial.read();
    Serial.print("Alınan Komut: ");
    Serial.println(command);

    // Motor hızını varsayılan olarak maksimuma ayarla (0-255)
    // İsteğe bağlı olarak gelen 'V' komutuyla hız ayarlanabilir.
    int motorSpeed = 200; // Varsayılan hız

    // Gelen komuta göre motorları kontrol et
    switch (command) {
      case 'F': // İleri
        forward(motorSpeed);
        break;
      case 'B': // Geri
        backward(motorSpeed);
        break;
      case 'L': // Sola Dön (yerinde)
        turnLeft(motorSpeed);
        break;
      case 'R': // Sağa Dön (yerinde)
        turnRight(motorSpeed);
        break;
      case 'S': // Dur
        stopMotors();
        break;
      case 'T': // Tam Sola Dön (Bir motor ileri, bir motor geri veya bir motor duruk)
        // Bu komutlar için kendi motor mantığınızı uygulayın.
        // Örnek: Sol teker geri, sağ teker ileri
        digitalWrite(in1, LOW); digitalWrite(in2, HIGH); // Sol motor geri
        digitalWrite(in3, HIGH); digitalWrite(in4, LOW); // Sağ motor ileri
        analogWrite(enA, motorSpeed); analogWrite(enB, motorSpeed);
        break;
      case 'D': // Tam Sağa Dön
        // Örnek: Sol teker ileri, sağ teker geri
        digitalWrite(in1, HIGH); digitalWrite(in2, LOW); // Sol motor ileri
        digitalWrite(in3, LOW); digitalWrite(in4, HIGH); // Sağ motor geri
        analogWrite(enA, motorSpeed); analogWrite(enB, motorSpeed);
        break;
      case 'X': // İleri Sol
        // Örnek: Sol motor yavaş, sağ motor hızlı veya sol motor duruk, sağ motor ileri
        analogWrite(enA, motorSpeed / 2); // Sol motor yavaş
        analogWrite(enB, motorSpeed);     // Sağ motor hızlı
        digitalWrite(in1, HIGH); digitalWrite(in2, LOW); // İleri
        digitalWrite(in3, HIGH); digitalWrite(in4, LOW); // İleri
        break;
      case 'M': // İleri Sağ
        analogWrite(enA, motorSpeed);     // Sol motor hızlı
        analogWrite(enB, motorSpeed / 2); // Sağ motor yavaş
        digitalWrite(in1, HIGH); digitalWrite(in2, LOW); // İleri
        digitalWrite(in3, HIGH); digitalWrite(in4, LOW); // İleri
        break;
      // N, Y komutları ve diğer özel hareketler için benzer mantıklar eklenebilir.
      // case 'V': // Hız komutu (örnek: 'V150' gibi bir format bekleniyorsa ek parse işlemi gerekir)
      //   // Gelen hız değerini okuma mantığı buraya eklenebilir.
      //   break;
      default: // Bilinmeyen komut
        stopMotors();
        break;
    }
  }
}

void forward(int speed) {
  digitalWrite(in1, HIGH);
  digitalWrite(in2, LOW);
  digitalWrite(in3, HIGH);
  digitalWrite(in4, LOW);
  analogWrite(enA, speed);
  analogWrite(enB, speed);
}

void backward(int speed) {
  digitalWrite(in1, LOW);
  digitalWrite(in2, HIGH);
  digitalWrite(in3, LOW);
  digitalWrite(in4, HIGH);
  analogWrite(enA, speed);
  analogWrite(enB, speed);
}

void turnLeft(int speed) { // Sol motor geri, sağ motor ileri (yerinde dönüş)
  digitalWrite(in1, LOW);
  digitalWrite(in2, HIGH);
  digitalWrite(in3, HIGH);
  digitalWrite(in4, LOW);
  analogWrite(enA, speed);
  analogWrite(enB, speed);
}

void turnRight(int speed) { // Sol motor ileri, sağ motor geri (yerinde dönüş)
  digitalWrite(in1, HIGH);
  digitalWrite(in2, LOW);
  digitalWrite(in3, LOW);
  digitalWrite(in4, HIGH);
  analogWrite(enA, speed);
  analogWrite(enB, speed);
}

void stopMotors() {
  digitalWrite(in1, LOW);
  digitalWrite(in2, LOW);
  digitalWrite(in3, LOW);
  digitalWrite(in4, LOW);
  // veya hızları sıfırla:
  // analogWrite(enA, 0);
  // analogWrite(enB, 0);
}
Not: Yukarıdaki Arduino kodu temel bir örnektir. Kendi motor sürücünüze ve araba yapınıza göre düzenlemeniz gerekebilir.
स्क्रीनशॉट / Ekran Görüntüleri (Opsiyonel)
 
🤝 Katkıda Bulunma
Katkılarınızı bekliyoruz! Lütfen bir "issue" açın veya bir "pull request" gönderin.
Projeyi Forklayın
Yeni bir Feature Branch oluşturun (git checkout -b feature/HarikaBirOzellik)
Değişikliklerinizi Commit edin (git commit -m 'Harika bir özellik eklendi')
Branch'inizi Push edin (git push origin feature/HarikaBirOzellik)
Bir Pull Request açın
📝 Lisans
Bu proje MIT Lisansı altında lisanslanmıştır. Daha fazla bilgi için LICENSE.md dosyasına bakın.

📧 İletişim
[irtengunica] - [@irtengunica] - [irtengunica@gmail.com]
Proje Linki: https://github.com/irtengunica/bluetooth_araba_kontrol.git
