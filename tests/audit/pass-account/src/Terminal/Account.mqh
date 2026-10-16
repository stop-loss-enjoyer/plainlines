// Fixture: the one file allowed to read ACCOUNT_LOGIN (in memory only).
static long g_login_fixture=0;
bool Changed() { long l=AccountInfoInteger(ACCOUNT_LOGIN); bool c=(l!=g_login_fixture); g_login_fixture=l; return(c); }
