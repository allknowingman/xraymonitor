# xraymonitor
 این اسکریپت به طور مداوم وضعیت اتصال خروجی سرور را از طریق یک کانفیگ تست Xray بررسی کرده و در صورت بروز قطعی، دستورات سفارشی شما را برای بازیابی خودکار اجرا می‌کند.

بعنوان مثال میتونید در کنار تانل های ریورس مثل Waterwall که هرازچندگاهی کانکشن مختل میشه استفاده کنید تا سرویس Waterwall رو مانیتور کنید تا دستور ریستارت تانل بصورت اتوماتیک اجرا بشه.


## ویژگی های کلیدی


:green_circle: مانیتورینگ خودکار و دوره‌ای اتصال به اینترنت <br>

:green_circle: اجرای دستور سفارشی کاربر در صورت بروز خطا مانند ری‌استارت یک سرویس خاص <br>

:green_circle: قابلیت ریبوت خودکار سرور پس از تعداد مشخصی خطای متوالی <br>

:green_circle: ارسال نوتیفیکیشن از طریق ربات تلگرام (برای سرورهای خارج از ایران) <br>

:green_circle: منوی مدیریتی ساده و کاربرپسند تحت ترمینال (TUI) برای نصب، حذف و مدیریت <br>

:green_circle: داشبورد نمایش وضعیت شامل سلامت سرویس، وضعیت آخرین اجرا و زمان باقی‌مانده تا اجرای بعدی <br>

:green_circle: بررسی خودکار پیش‌نیازها قبل از نصب برای جلوگیری از بروز خطا <br>





##

It continuously checks the server's outbound connection status using a test Xray config. If a disconnection occurs, it executes your custom commands to automatically recover the connection.

## Key Features

* Automatic, periodic monitoring of the internet connection.

* Executes a user-defined custom command on failure (e.g., restarting a service).

* Option to automatically reboot the server after a set number of consecutive failures.

* Sends notifications via a Telegram bot (for non-Iran servers).

* Simple, terminal-based user interface (TUI) for easy installation, uninstallation, and management.

* Status dashboard showing service health, last run status, and time until the next check.

* Automatically checks for dependencies before installation.

## Quick Start

```bash
bash <(curl -Ls https://raw.githubusercontent.com/allknowingman/xraymonitor/main/xray-monitor.sh)
```

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./media/menu%20screenshot.png">
    <img alt="xraymonitor" src="./media/menu%20screenshot.png.png">
  </picture>
</p>
