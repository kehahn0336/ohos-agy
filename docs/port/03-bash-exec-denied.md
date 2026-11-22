# 03 · `fork/exec .../bash: permission denied`

## 现象

过了内核版本检查和 SIGSYS 两关之后，命令依然是“跑了但什么都没发生”。用 `--output-format stream-json` 才能看到真实错误：

```sh
agy --dangerously-skip-permissions -p "执行 echo hello" --output-format stream-json
```

```json
"output": "Command failed to run: remote error: run bash: fork/exec
/data/storage/el1/bundle/libs/arm64/bash/bin/bash: permission denied."
```

模型会把它解释成“bash 没有执行权限”，容易带偏。

## 原因

agy 执行命令时用 `exec.LookPath("bash")` 找 shell。而当前 PATH 里唯一的 bash 是 **WorkBuddy HAP 自带的那个**：

```
/data/storage/el1/bundle/libs/arm64/bash/bin/bash
```

`/data/storage/el1/bundle/**` 是应用的只读安装区。**第三方（自签名）ELF 不能 exec 里面的二进制**——内核/安全模块直接拒绝，返回 `EACCES`。

agy 自己也在 `~/opt/agy/`（用户区），所以它连“另一个区里的 bash”都拉不起来。

## 无效的尝试

```sh
SHELL=/bin/sh agy ...          # 无效，它不读 SHELL
env -u BASH SHELL=/bin/sh ...  # 无效
```

agy 只认 `LookPath`，也就是 **PATH 顺序**。

## 解法：自签名 bash 放 PATH 最前

```sh
cp ~/.harmonybrew/bin/bash ~/opt/bin/bash     # 这个软链最终指向 /data/service/hnp/bin/bash
binary-sign-tool sign -inFile ~/opt/bin/bash -outFile ~/opt/bin/bash.s -selfSign 1
mv ~/opt/bin/bash.s ~/opt/bin/bash
chmod +x ~/opt/bin/bash
~/opt/bin/bash -c 'echo ok'                   # 必须能跑，否则说明签名没成功
```

再把 `~/opt/bin` 前置到 PATH：

```sh
export PATH="$HOME/opt/bin:$PATH"
```

启动器 `~/opt/bin/agy` 里已经写了这一行，所以用启动器就不用手动加。

### 为什么必须先签名

直接 `cp` 过来的 ELF 跑不起来：

```
$ ~/opt/bin/bash -c 'echo ok'
Permission denied
$ echo $?
126
```

鸿蒙要求所有可执行 ELF 带代码签名（自签即可）。这跟 agy 二进制本身要签名是同一件事。

## 自检

```sh
$ which bash
~/opt/bin/bash      # 必须是用户区这个
$ ~/opt/bin/bash -c 'echo ok'
ok
$ agy -p "运行 echo hello"
```

成功时 `stream-json` 里是：

```json
"output": "Command exited with code 0.\n\nCommand output:\nhello\n"
```
