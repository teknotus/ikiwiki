#!/usr/bin/perl
# based on Ikiwiki skeleton plugin.

# Copyright (c) 2008 David Bremner <bremner@unb.ca>
# This file is distributed under the Artistic License/GPL2+

use Email::FolderType qw(folder_type);
use Email::MIME;
package Email::MIMEFolder;
use base 'Email::Folder';
sub bless_message { return  Email::MIME->new($_[1]) };


package IkiWiki::Plugin::mailbox;

use IkiWiki 2.00;
use Email::Thread;
use CGI 'escapeHTML';
use Data::Dumper;



my %metaheaders;


sub import { #{{{
	hook(type => "preprocess", id => "mailbox", call => \&preprocess);
	hook(type => "scan", id => "mailbox", call => \&scan);
	hook(type => "pagetemplate", id=>"mailbox", call => \&pagetemplate);
	IkiWiki::loadplugin("filecheck");
} # }}}

sub scan(@){
	my %params=@_;
	my $page=$params{page};

	push @{$metaheaders{$page}}, 
	       '<link rel="stylesheet" href="mailbox.css" type="text/css"/>'
}

sub preprocess (@) { #{{{
	my %params=@_;
	
	my $page=$params{page};
	my $type=$params{type} || 'Maildir';

	my $path=$params{path} ||  error gettext("missing parameter") . " path";
	
	# hmm, this should probably only be inserted once per page.

	my $dir=bestpath($page,$params{path}) || 
	    error("could not find ".$params{path});

	$params{path} = $config{srcdir} ."/" . $dir;
	$params{type} = $type;
	
	return  format_mailbox(%params);

} # }}}


### The guts of the plugin
### parameters 
sub format_mailbox(@){
    my %params=@_;
    my $path=$params{path} || error gettext("missing parameter "). 'path';
    my $type=$params{type} || error gettext("missing paramater ")."type";

    debug('type='.$type);
    my $folder=Email::MIMEFolder->new($path,reader=>'Email::Folder::'.$type) || error("mailbox could not be opened");
    my $threader=new Email::Thread($folder->messages);

    $threader->thread();

    return join "\n", map { format_thread(thread=>$_) } $threader->rootset;
}

sub format_thread(@){
    my %params=@_;
    
    my $thread=$params{thread} || error gettext("missing parameter") . "thread";

    my $output="";

    if ($thread->message) {
	$output .= format_message(message=>$thread->message);
    } else {
	$output .= sprintf gettext("Message %s not available"), $thread->messageid;
    }

    if ($thread->child){
	$output .= '<div class="emailthreadindent">' .
	    format_thread(thread=>$thread->child).
	    '</div>';
    }

    if ($thread->next){
	$output .= format_thread(thread=>$thread->next);
    }
    return $output;
}

sub make_pair($$){
    my $message=shift;
    my $name=shift;
    my $val=$message->header($_);
    
    $val = escapeHTML($val);

    my $hash={'HEADERNAME'=>$name,'VAL'=>$val};
    return $hash;
}
sub format_message(@){
    my  %params=@_;

    my $message=$params{message} || 
	error gettext("missing parameter"). "message";

    my $keep_headers=$params{headers} || qr/^(subject|from|date)[:]?$/i;
    
    my $template= 
	template("email.tmpl") || error gettext("missing template");

    my $output="";

    my @names = grep  {m/$keep_headers/;}  ($message->header_names);
    my @headers=map { make_pair($message,$_) } @names;
    

    $template->param(HEADERS=>[@headers]);

    my $filter=$params{filter} ||  "maxsize(100k) and mimetype(text/plain)";
    my @good_parts=filter_parts($filter,$message->parts;

    my $body= join("\n", map { $_->body }  $message->parts);

    $template->param(body=>format_body($body));

    $output .= $template->output();
    return $output;
}

sub format_body($){
    my $body=shift;

    # it is not completely clear to me the right way to go here.  
    # passing things straight to markdown is not working all that
    # well.
    return "<pre>".escapeHTML($body)."</pre>";
}
### Utilities

# based on bestdir From Arpit Jain
# http://ikiwiki.info/todo/Bestdir_along_with_bestlink_in_IkiWiki.pm/
# need to clarify license
sub bestpath ($$) { #{{{
    my $page=shift;
       my $link=shift;
       my $cwd=$page;

       if ($link=~s/^\/+//) {
               $cwd="";
       }

       do {
               my $l=$cwd;
               $l.="/" if length $l;
               $l.=$link;
               if (-d "$config{srcdir}/$l" || -f "$config{srcdir}/$l") {
                       return $l;
               }
       } while $cwd=~s!/?[^/]+$!!;

       if (length $config{userdir}) {
               my $l = "$config{userdir}/".lc($link);

               if (-d $l || -f $l) {
                       return $l;
               }
       }

       return "";
} #}}}

sub pagetemplate (@) { #{{{
	my %params=@_;
        my $page=$params{page};
        my $destpage=$params{destpage};
        my $template=$params{template};

	if (exists $metaheaders{$page} && $template->query(name => "meta")) {
		# avoid duplicate meta lines
		my %seen;
		$template->param(meta => join("\n", grep { (! $seen{$_}) && ($seen{$_}=1) } @{$metaheaders{$page}}));
	}
}



package Email::FolderType::MH;

sub match {
    my $folder = shift;
    return 0 if (! -d $folder);
    opendir DIR,$folder || error("opendir failed");

    while (<DIR>){
      return 0 if (!m|\.| && !m|\.\.| && !m|\d+|);
    }
    return 1;
}



1;
