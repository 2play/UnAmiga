#include <stdio.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <unistd.h>
//#include <io.h>


int main(int argc, char *argv[])
{
	int  fp, write_ok;
	long kb, kb_left;
	char **end_ptr;
	char one_kb_str[1025];
	char fill_char;

	printf ("\n\nFill File Create Utility\n\n");

    if (argc < 3) {                                                      
        printf ("Usage %s filename filesize_in_KB [fill_character]\n\n", argv[0]);
    }                                                                    
                                                                         
//    else if (access(argv[1], 0) != -1) {
//		printf ("The file %s already exists!\n\n",argv[1]);
//	}

	else if ((fp=open(argv[1], O_CREAT|O_RDWR, S_IREAD|S_IWRITE)) == -1) {
		printf ("Unable to open the file %s!\n\n",argv[1]);
	}

	else {

		if (argc > 3) {
			fill_char = argv[3][0];
		}

		else {
			fill_char = ' ';
		}

		for (kb = 0; kb < 1024; kb++) {
			one_kb_str[kb] = fill_char;	
		}

		/* write a K at a time */
		for (kb_left = kb = strtol(argv[2], end_ptr, 10), write_ok = 1;
				(kb_left > 0L) && (write_ok);
				kb_left--) {

			if (write(fp, one_kb_str, 1024) != 1024) {
				write_ok = 0;
			}
			
			else {
				printf ("%ld KB written, %ld KB still to write.    \r ",
						kb - kb_left,
						kb_left);
			}
		}

		if (! write_ok) {
			printf ("\n\nWrite to file %s failed.  May be out of disk space!\n\n",argv[1]);
		}

		else {
			printf ("%ld KB written, %ld KB still to write.     \n\nDone!\n\n ",
					kb - kb_left,
					kb_left);
		}

		close (fp);
	}

	exit(0);
}
