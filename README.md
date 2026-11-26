# Ataç — Ultra Hafif macOS Pano (Clipboard) Yöneticisi

> **Alpha Sürüm 0.1** · *Ensar Gemici katkılarıyla*

Maccy'den ilham alınarak **saf Swift + AppKit** ile geliştirilmiş; Electron, WebView, SwiftUI veya ağır veritabanı katmanları içermeyen, arka planda sıfıra yakın CPU, GPU ve RAM tüketen yerel macOS menü çubuğu (menu bar) pano geçmişi uygulaması.

## Özellikler
- **%0 Boşta GPU ve Minimum RAM (Geçici Pencere Mimarisi):** Açılır geçmiş penceresi yalnızca üst bardaki **ataç** ikonuna tıkladığınızda veya kısayola bastığınızda oluşturulur; kapandığı anda pencere ve katmanlar bellekten tamamen serbest bırakılır.
- **Sıfıra Yakın CPU İzleme:** Pano içeriği her tikte okunmaz; yalnızca `NSPasteboard.general.changeCount` kontrol edilir ve esnek zamanlayıcı toleransı (`leeway`) ile macOS çekirdeği uyanmaları birleştirir. Ekran uyuduğunda izleyici tamamen durur.
- **Kopyalanan Dosyaları Tek Tıkla Açma:** Finder'dan kopyaladığınız `.txt`, `.pdf`, görsel veya klasörlere listeden tıkladığınızda varsayılan uygulamasıyla doğrudan açılır (`⌘R` ile Finder'da gösterir).
- **Görseller RAM'de Tutulmaz:** Ekran görüntüleri sıkıştırılmış PNG olarak diske yazılır; RAM'de yalnızca üstveri tutulur, silinen veya taşan öğelerin disk dosyaları otomatik temizlenir.
- **Şifre Yöneticisi Koruması:** 1Password, Bitwarden ve Apple Parolalar gibi uygulamalardan kopyalanan gizli veriler otomatik yoksayılır.
- **Türkçe Duyarsız Anlık Arama ve Sabitleme:** `isik` yazarak `Işık` öğesini bulabilme, `⌥P` ile önemli metinleri en üste sabitleme ve `⌘1`…`⌘9` ile hızlı seçim.

## Kısayollar

| Kısayol | İşlev |
| :--- | :--- |
| **Üst bardaki ataç ikonu** | Pano geçmişini aç / kapat *(Sağ tık: Hızlı Ayarlar)* |
| **`⇧⌘C`** *(Ayarlardan değiştirilebilir)* | Herhangi bir uygulamadayken geçmişi aç / kapat |
| **İmleç ile üzerine gel / `↑` `↓`** | Öğeyi seç |
| **Tıkla / `↩` (Enter)** | Metin/bağlantıyı kopyalar; **dosyaysa doğrudan açar** |
| **`⌘R`** *(Dosya seçiliyken)* | Dosyayı Finder'da gösterir |
| **`⌘C`** *(Pencere açıkken)* | Dosyayı açmadan panoya geri kopyalar |
| **`⌥↩` (Option + Enter)** | Düz metin (veya dosya yolu) olarak kopyalar |
| **`⌘1` … `⌘9`** | İlk 9 öğeyi anında seçer |
| **`⌥P` veya `⌘P`** | Seçili öğeyi en üste sabitler / kaldırır |
| **`⌥⌫` (Option + Sil)** | Seçili öğeyi geçmişten siler |

---

## Başka Bir Mac'e İndirip Kurma

### Yöntem 1: Homebrew ile Tek Satırda Kurulum (En Kolay — Önerilen)
Homebrew kurulu herhangi bir Mac'te Terminal'e şu komutu yapıştırmanız yeterlidir (`.dmg` indirilir, **Uygulamalar** klasörüne kurulur ve Gatekeeper engeli otomatik kaldırılır):

```bash
brew tap skyeso/tap && brew install --cask skyeso/tap/atac
```

Güncellemek için `brew upgrade --cask atac`, kaldırmak için `brew uninstall --cask atac` komutunu kullanabilirsiniz.

### Yöntem 2: Hazır DMG Paketi ile Elle Kurulum (Derleme Gerekmez)
1. Bu deponun **Releases** sayfasından en güncel `Atac-v0.1-alpha-macOS.dmg` (veya `.zip`) dosyasını indirin.
2. `.dmg` dosyasını açıp **Ataç** simgesini **Applications (Uygulamalar)** klasörüne sürükleyin.
3. İlk açılışta macOS Gatekeeper uyarısı çıkarsa Terminal'de bir kez şu komutu çalıştırın:

```bash
xattr -cr "/Applications/Ataç.app"
open "/Applications/Ataç.app"
```

### Yöntem 3: Kaynak Koddan Tek Komutla Kurulum
Xcode Command Line Tools (`xcode-select --install`) kurulu bir Mac'te:

```bash
git clone https://github.com/skyeso/atac-macos.git
cd atac-macos
chmod +x build.sh install.sh
./install.sh
```

`./install.sh` uygulamayı otomatik derler, `/Applications/Ataç.app` konumuna kopyalar ve başlatır.
