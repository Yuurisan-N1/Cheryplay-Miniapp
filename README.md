<div align="center">

<img width="100%" alt="header" src="https://capsule-render.vercel.app/api?type=waving&height=210&text=Cherry%20Play%20Bot&fontAlign=50&fontAlignY=36&fontSize=56&desc=Streak%20%7C%20Lucky%20Spin%20%7C%20Task%20Board%20%7C%20Arcade%20Games%20%7C%20Ads&descAlign=50&descAlignY=58"/>

<img alt="typing" src="https://readme-typing-svg.demolab.com?font=Inter&size=18&duration=3000&pause=650&center=true&vCenter=true&width=900&lines=Telegram+initData+Login;Daily+Streak+%7C+Friend+Rewards;Lucky+Spin+%7C+Pending+Rewards;Task+Board+%7C+Arcade+Games;Sponsored+Ad+Tasks+%7C+Multi-Account"/>

<p>
  <img alt="elixir" src="https://img.shields.io/badge/Elixir-1.14%2B-4B275F?logo=elixir&logoColor=white"/>
  <img alt="platform" src="https://img.shields.io/badge/Platform-Cherry%20Play%20Miniapp-111111"/>
  <img alt="multi-account" src="https://img.shields.io/badge/Multi--Account-Supported-111111"/>
  <img alt="proxy" src="https://img.shields.io/badge/Proxy-Supported-111111"/>
  <img alt="author" src="https://img.shields.io/badge/by-Yuurisandesu-111111"/>
</p>

<p>
  <b>Cherry Play Bot</b> is a full automation bot for the Cherry Play Telegram Miniapp.<br/>
  It logs every account in with the Telegram <code>initData</code> from <code>data.txt</code>, claims the daily streak, collects friend rewards, runs all lucky spins (earning extra ones from ads when empty), settles pending rewards, walks the full task board including ad-gated tasks, plays every available arcade game, runs the sponsored ad tasks, and reports the final cherry balance at the end of each cycle.<br/>
  Built and distributed by <b>Yuurisandesu</b>.
</p>

</div>

---

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Running the Bot](#running-the-bot)
- [Features](#features)
- [File Structure](#file-structure)
- [Disclaimer](#disclaimer)

---

## Requirements

- Elixir `1.14+` with Erlang/OTP `25+`
- Git

---

## Installation

### Install Elixir

Elixir runs on the Erlang virtual machine, so **Erlang/OTP is required** - Elixir cannot run without it. Every package manager below installs Erlang/OTP for you as a dependency. The only path that needs a separate Erlang step is the Windows manual installer (see below).

**Windows:**

*Option A - package manager (recommended, installs Erlang automatically):*

```cmd
winget install Elixir.Elixir
```

*Option B - manual installer (two installers, in this order):*

1. Download and run the **Erlang/OTP installer** from https://www.erlang.org/downloads
2. Run `erl -s halt` to check which OTP version you got
3. Download the **Elixir installer built for that exact OTP** from https://elixir-lang.org/install.html (`elixir-otp-<N>.exe`) and run it

Then open Command Prompt and verify:

```cmd
elixir --version
```

The output prints both versions, for example `Elixir 1.14.0 (compiled with Erlang/OTP 25)`.

**Linux (Ubuntu / Debian):**

```bash
sudo apt-get update
sudo apt-get install -y elixir
elixir --version
```

**macOS:**

```bash
brew install elixir
elixir --version
```

> If you do not have Homebrew, install it first from https://brew.sh

**Termux (Android):**

```bash
pkg update && pkg upgrade -y
pkg install elixir -y
elixir --version
```

> If the `elixir` package is not available in your Termux repository, install an Ubuntu environment first with `pkg install proot-distro`, then `proot-distro install ubuntu`, then `proot-distro login ubuntu` and run the Linux command above inside it.

---

### Clone and Install

**Clone the repository:**

```bash
git clone https://github.com/Yuurisan-N1/Cheryplay-Miniapp.git
cd Cheryplay-Miniapp
```

**Install dependencies:**

This bot uses only the Elixir standard library, so there is nothing to install. Erlang/OTP was already installed by the step above.

---

## Configuration

### 1. Accounts (data.txt)

Fill `data.txt` with the Telegram WebApp `initData` of each account, one per line:

```
user=%7B%22id%22...&hash=abc123
user=%7B%22id%22...&hash=def456
```

> `initData` can be obtained from the browser DevTools when opening the Cherry Play Miniapp on Telegram Web.

### 2. Proxy (proxy.txt)

Fill `proxy.txt` with proxies, one per line (optional, leave empty to run without proxy):

```
host:port
host:port:user:pass
http://user:pass@host:port
```

Proxies are assigned to accounts by index in round-robin order. Proxy credentials are masked in the log.

### 3. Bot Settings (config.json)

`sleep_seconds` controls how many seconds the bot waits between cycles. If `config.json` is missing, it is created automatically with a default of `3600` seconds.

```json
{
  "settings": {
    "sleep_seconds": 3600
  }
}
```

---

## Running the Bot

**Linux / macOS:**

```bash
elixir --erl "+Bd" bot.exs
```

**Windows:**

```cmd
elixir --erl "+Bc" bot.exs
```

Or just double click `run_pc.bat`, which runs the Windows command above.

---

## Features

### Account Login
Every account is opened with the Telegram `initData` from `data.txt`. The bot reads the bootstrap state, logs the account index together with the current cherry balance, and then runs the full reward cycle.

### Daily Streak
The streak state is read before it is claimed. When the day is still open the claim is sent and the streak day number is logged. An already collected day is reported and skipped. If the account has not set a Telegram bio invite link yet, a note is logged instead of an error.

### Friend Rewards
The pending referral balance is checked before the claim is sent. When referral cherries are ready the claim is submitted and the credited amount is logged. If nothing is pending, the step is skipped.

### Lucky Spin
The available spin count is read from the account state. Each spin is used one by one and the prize is logged as it lands. When all spins are used up the bot watches one rewarded advertisement to earn an extra spin and uses it immediately.

### Pending Rewards
All pending reward items are read from the bootstrap state. Each item is claimed individually. If the server requires watching more ads before the claim is accepted, the bot watches the required number of ads and retries the claim. A claim that is on cooldown waits for the server-reported time before retrying.

### Task Board
Regular tasks are started, verified if the server requests a wait, and then claimed. Each claimed task is logged with its title and cherry reward. Ad-gated tasks require watching a rewarded advertisement before the claim is accepted; the bot handles both steps automatically. Tasks the server refuses are skipped instead of stopping the cycle.

### Arcade Games
Every game that still has plays left is run to completion. Each session is started on hard difficulty, played for the minimum server-reported time, and finished with a random score. The reward is logged per session. If the server asks to settle a previous pending reward before starting, the bot claims it first and then continues.

### Sponsored Ad Tasks
The remaining sponsored ad task quota is read from the bootstrap state. Each available slot is filled by watching an advertisement. The paid cherry amount is logged per ad. A cooldown between ads is respected with a live countdown. Tasks that are not available on the account are skipped with a note.

### Balance Report
At the end of every cycle the bootstrap state is read once more and the final cherry balance is logged.

### Multi Account
All accounts in `data.txt` are processed sequentially within every cycle. Each account is logged with its index and balance. The cycle number is tracked and logged at the start of each round.

### Proxy Support
Proxies are loaded from `proxy.txt` and assigned to accounts by position in round-robin order. Running without proxies is fully supported.

### Auto Countdown
After all accounts complete a cycle the bot shows a live `HH:MM:SS` countdown until the next cycle starts.

---

## File Structure

```text
Cheryplay-Miniapp/
├── utils/
│   ├── banner.ex                        # Banner display and terminal title on startup
│   └── json.ex                          # JSON encoder and decoder
├── bot.exs                              # Main bot, full Cherry Play cycle automation
├── config.json                          # Sleep duration between cycles
├── data.txt                             # Account initData, one per line
├── proxy.txt                            # Proxy list, one per line (optional)
├── run_pc.bat                           # Launcher for Windows
├── LICENSE                              # License file
└── README.md                            # This file
```

---

## Disclaimer

This tool is built for educational and technical exploration purposes. Use it wisely and at your own responsibility.

---

<div align="center">
<img width="100%" alt="footer" src="https://capsule-render.vercel.app/api?type=waving&height=120&section=footer"/>
</div>