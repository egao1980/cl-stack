# Java and Python libraries from Common Lisp

How to call a Java or Python library from a cl-stack app, and what the stack ships for it. Prefer a cl-stack protocol when one covers the need. These routes are for libraries the stack has no equivalent for, and for the JVM backends on ABCL.

## Java

There are two routes, and they don't mix:

| Route | Runtime | Use it for |
|-------|---------|-----------|
| **ABCL** (real JVM) | ABCL 1.9.x on a JDK | Anything on the classpath: `java:jstatic`, `java:jnew`, `java:jcall`, `java:add-to-classpath`. The JVM backends below. |
| **OpenLDK** (no JVM) | SBCL, outside Windows | Pure-Java jars translated to Lisp: small utility libraries, no JVM process |

### ABCL backends

They bind themselves on `#+abcl`. On other implementations they load stubs that signal when called.

| System | Version | Role |
|--------|---------|------|
| [`cl-stack-icu4j`](https://github.com/egao1980/cl-stack-icu4j) | **79.1.0** | ICU4J 79.1 jar on the classpath, plus a Lisp API over `com.ibm.icu.*` |
| [`unicode-backend-icu4j`](https://github.com/egao1980/unicode-backend-icu4j) | **0.1.2** | `unicode-protocol` on ICU4J |
| [`i18n-backend-icu4j`](https://github.com/egao1980/i18n-backend-icu4j) | **0.1.1** | `i18n-protocol` on ICU4J |
| [`l10n-backend-icu4j`](https://github.com/egao1980/l10n-backend-icu4j) | **0.1.2** | `l10n-protocol` on ICU4J |
| [`http-backend-java`](https://github.com/egao1980/http-backend-java) | **0.1.1** | `http-protocol` / `ws-protocol` on `java.net.http` (HTTP/1.1, HTTP/2, WebSocket) |
| [`event-backend-nio`](https://github.com/egao1980/event-backend-nio) | **0.1.2** | `event-protocol` on NIO `Selector`. Prefer it over libuv on ABCL. |

ABCL needs a JDK, and CFFI on ABCL needs the JNA jars on `CLASSPATH`. CI setup and the other ABCL pitfalls are in [multi-impl.md](../multi-impl.md#abcl-pitfalls-agents--ci). A gRPC backend on the JVM (`grpc-backend-java`) is planned ([grpc.md](grpc.md)).

### OpenLDK on SBCL

[`java-backend-openldk`](https://github.com/egao1980/java-backend-openldk) **0.1.1** (nickname `ldk-java`) loads Java libraries on SBCL through [OpenLDK](https://github.com/atgreen/openldk) 1.0.2, which translates JVM bytecode to Lisp. OpenLDK is an unmodified `cl-stack-systems` import. The loader calls only `openldk.interop`. It downloads jars with `cl-stack-http`, checks their SHA-256 with `crypto-protocol`, and builds paths with `cl-stack-pathlib`.

```lisp
(asdf:load-system "crypto-backend-ironclad")
(asdf:load-system "http-backend-async")      ; or another cl-stack-http backend
(asdf:load-system "java-backend-openldk")

(ldk-java:add-maven-jar "org.apache.commons:commons-lang3:3.17.0" :sha256 "…")
(ldk-java:jstatic "java.lang.Math" "max(II)" 3 4)   ; => 4
```

Limits:
- `JAVA_HOME` must point to a JDK 25, which supplies the class library. OpenLDK can fetch Temurin itself, but only on Linux.
- No Windows: OpenLDK uses `sb-posix:mmap`, which Windows SBCL doesn't export. The download and checksum code still loads there.
- Not every JDK class is implemented. For example, `java.security.MessageDigest` is missing, so Commons Codec `DigestUtils` fails.
- Licence: OpenLDK is GPL-3.0-or-later with the Classpath exception. `java-backend-openldk` itself is MIT.

Demo: [`java-ldk-demo`](https://github.com/egao1980/java-ldk-demo) calls Commons Lang `StringUtils.reverse` on SBCL with no JVM.

## Python

The stack has no Python bridge, and no cl-stack library runs CPython. Use one of these:

| Need | Route |
|------|-------|
| Run a Python script or tool and read its output | [`process-protocol`](process.md) (`uv run …` as a subprocess), with JSON over stdout via `json-protocol` |
| Call Python objects from Lisp | Third-party [py4cl2](https://github.com/digikar99/py4cl2), which runs Python as a subprocess, or [py4cl2-cffi](https://github.com/digikar99/py4cl2-cffi), which embeds CPython through CFFI. Neither is in cl-repo yet. A request for one goes through a `cl-stack-systems` import. |
| Exchange data with Python | `arrow-protocol` (Arrow IPC / Parquet), `messagepack-protocol`, `json-protocol`. `pickle` is not supported ([STDLIB-MODULES.md](../STDLIB-MODULES.md)). |

Inside the stack, Python serves only as a test oracle. Gold vectors come from CPython libraries (`holidays`, `exchange_calendars`, `codecs`, `email`, `dateutil`), generated with `uv run` and frozen as fixtures. See [datetime.md](datetime.md) and the encoding-protocol and cl-stack-calendars test data.

The [Python to Common Lisp](https://egao1980.github.io/python-to-cl/) site has worked examples: py4cl2 with PyTorch and transformers on its [PyTorch page](https://egao1980.github.io/python-to-cl/pytorch.html).
