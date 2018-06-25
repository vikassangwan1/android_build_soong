// Copyright 2017 Google Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package config

import (
	"strings"

	"android/soong/android"
)

func init() {
	android.RegisterMakeVarsProvider(pctx, makeVarsProvider)
}

func makeVarsProvider(ctx android.MakeVarsContext) {
	ctx.Strict("TARGET_DEFAULT_JAVA_LIBRARIES", strings.Join(DefaultLibraries, " "))

	ctx.Strict("DEFAULT_JAVA_LANGUAGE_VERSION", "${DefaultJavaVersion}")

	ctx.Strict("ANDROID_JAVA_HOME", "${JavaHome}")
	ctx.Strict("ANDROID_JAVA_TOOLCHAIN", "${JavaToolchain}")
	ctx.Strict("JAVA", "${JavaCmd}")
	ctx.Strict("JAVAC", "${JavacCmd}")
	ctx.Strict("JAR", "${JarCmd}")
	ctx.Strict("JAR_ARGS", "${JarArgsCmd}")
	ctx.Strict("JAVADOC", "${JavadocCmd}")
	ctx.Strict("COMMON_JDK_FLAGS", "${CommonJdkFlags}")
	ctx.Strict("DX", "${DxCmd}")
	ctx.Strict("DX_COMMAND", "${DxCmd} -JXms16M -JXmx2048M")
	if ctx.Config().IsEnvTrue("EXPERIMENTAL_USE_OPENJDK9") {
		ctx.Strict("JLINK", "${JlinkCmd}")
		ctx.Strict("JMOD", "${JmodCmd}")
	}
}
