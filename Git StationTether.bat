@Echo off

set repo=.git-stationtether

xcopy /Y /H /I /S /E %repo% .git
"%ProgramFiles%\Git\git-bash.exe" -c "echo Repository: %repo% && /usr/bin/bash --login -i"
xcopy /Y /H /I /S /E .git %repo%
del /S /Q /F .git