// expect: FileOpen with a numeric
int OnInit(){int h=FileOpen("a.txt",FILE_WRITE|1<<12);return(0);}
