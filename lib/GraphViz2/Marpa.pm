package GraphViz2::Marpa;

use strict;
use utf8;
use warnings;
use warnings  qw(FATAL utf8);    # Fatalize encoding glitches.
use open      qw(:std :utf8);    # Undeclared streams in UTF-8.
use charnames qw(:full :short);  # Unneeded in v5.16.

use File::Slurp; # For read_file().

use GraphViz2::Marpa::Renderer::GraphViz2;

use Log::Handler;

use Marpa::R2;

use Moo;

use Tree::DAG_Node;

use Types::Standard qw/Any ArrayRef Int Str/;

use Try::Tiny;

has brace_count =>
(
	default  => sub{return 0},
	is       => 'rw',
	isa      => Int,
	required => 0,
);

has description =>
(
	default  => sub{return ''},
	is       => 'rw',
	isa      => Str,
	required => 0,
);

has grammar =>
(
	default  => sub {return ''},
	is       => 'rw',
	isa      => Any,
	required => 0,
);

has graph_text =>
(
	default  => sub{return ''},
	is       => 'rw',
	isa      => Str,
	required => 0,
);

has input_file =>
(
	default  => sub{return ''},
	is       => 'rw',
	isa      => Str,
	required => 0,
);

has logger =>
(
	default  => sub{return undef},
	is       => 'rw',
	isa      => Any,
	required => 0,
);

has maxlevel =>
(
	default  => sub{return 'info'},
	is       => 'rw',
	isa      => Str,
	required => 0,
);

has minlevel =>
(
	default  => sub{return 'error'},
	is       => 'rw',
	isa      => Str,
	required => 0,
);

has output_file =>
(
	default  => sub{return ''},
	is       => 'rw',
	isa      => Str,
	required => 0,
);

has recce =>
(
	default  => sub{return ''},
	is       => 'rw',
	isa      => Any,
	required => 0,
);

has renderer =>
(
	default  => sub{return ''},
	is       => 'rw',
	isa      => Any,
	required => 0,
);

has stack =>
(
	default  => sub{return []},
	is       => 'rw',
	isa      => ArrayRef,
	required => 0,
);

has tree =>
(
	default  => sub{return ''},
	is       => 'rw',
	isa      => Any,
	required => 0,
);

has uid =>
(
	default  => sub{return 0},
	is       => 'rw',
	isa      => Int,
	required => 0,
);

our $VERSION = '2.00';

# --------------------------------------------------

sub BUILD
{
	my($self) = @_;

	if (! defined $self -> logger)
	{
		$self -> logger(Log::Handler -> new);
		$self -> logger -> add
		(
			screen =>
			{
				maxlevel       => $self -> maxlevel,
				message_layout => '%m',
				minlevel       => $self -> minlevel,
			}
		);
	}

	$self -> grammar
	(
		Marpa::R2::Scanless::G -> new
		({
source					=> \(<<'END_OF_GRAMMAR'),

:default				::= action => [values]

lexeme default			= latm => 1    # Active the Longest Acceptable Token Match option.

:start 					::= graph_definition

# The prolog to the graph.

graph_definition		::= graph_body
							| comments graph_body
							| graph_body comments
							| comments graph_body comments

comments				::= comment+

comment					::= <C style comment>
							| <Cplusplus style comment>
							| <hash comment>

graph_body				::= prolog_tokens graph_statement_tokens

prolog_tokens			::= strict_token graph_type global_id_type

strict_token			::=
strict_token			::= strict_literal

graph_type				::= digraph_literal
							| graph_literal

global_id_type			::=
global_id_type			::= generic_id_token

# The graph proper.

graph_statement_tokens	::= open_brace statement_list close_brace

statement_list			::= statement_token*

statement_token			::= statement statement_terminator

statement_terminator	::= semicolon_literal
statement_terminator	::=

statement				::= node_statement
							| edge_statement
							| attribute_statement
							| assignment_statement
							| subgraph_statement
							| comments
# Node stuff.

node_statement			::= generic_id_token attribute_tokens

generic_id_token		::= generic_id
							| ('"') string ('"')
							| ('<') generic_id ('>')
							| number
							| ('"') number_list ('"')

number					::= float
							| integer

number_list				::= number
							| number comma_literal number_list

# Edge stuff.

edge_statement			::= edge_segment attribute_tokens

edge_segment			::= edge_tail edge_literal edge_head

edge_tail				::= edge_node_token
							| subgraph_statement

edge_head				::= edge_tail
							|  edge_tail edge_literal edge_head

edge_node_token			::= generic_id_token
							| node_port_id
							| node_port_compass_id

node_port_id			::= generic_id_token<colon>generic_id_token

node_port_compass_id	::= node_port_id<colon>generic_id_token

# Attribute stuff.
# These have no body between the '[]' because they is parsed manually in order to
# preserve whitespace in double-quoted strings, which is otherwise discarded by this grammar.
# See _process_attributes(). See also the same method for the handling of attribute terminators: [;,].

attribute_tokens		::=
attribute_tokens		::= open_bracket close_bracket statement_terminator

attribute_statement		::= node_statement # Search for 'class'! It's in _process().

# Assignment stuff.
# There is nothing after 'equals_literal' because it is parsed manually in order to
# preserve whitespace in double-quoted strings, which is otherwise discarded by this grammar.
# See _attribute_field().

assignment_statement	::= generic_id equals_literal generic_id_token

# Subgraph stuff.
# Subgraphs are handled by the statement type 'graph_statement_tokens'.
# Hence subgraph sub_1 {...} and subgraph {...} and sub_1 {...} and {...} are all output as:
# o The optional literal 'subgraph', which is classified as a literal.
# o The optional subgraph id, which is classified as a node_id.
# o The literal '{'.
# o The body of the subgraph.
# o The literal '}'.

subgraph_statement		::= subgraph_prefix subgraph_id_token graph_statement_tokens

subgraph_prefix			::=
subgraph_prefix			::= subgraph_literal

subgraph_id_token		::=
subgraph_id_token		::= generic_id_token

# Lexeme-level stuff, in alphabetical order.

:lexeme					~ close_brace		pause => before		event => close_brace

close_brace				~ '}'

:lexeme					~ close_bracket		pause => before		event => close_bracket

close_bracket			~ ']'

:lexeme					~ colon				pause => before		event => colon

colon					~ ':'

:lexeme					~ comma_literal		pause => before		event => comma_literal

comma_literal			~ ','

digit					~ [0-9]
digit_any				~ digit*
digit_many				~ digit+

:lexeme					~ digraph_literal	pause => before		event => digraph_literal

digraph_literal			~ 'digraph':i

:lexeme					~ edge_literal		pause => before		event => edge_literal

edge_literal			~ '->'
edge_literal			~ '--'

:lexeme					~ equals_literal	pause => before		event => equals_literal

equals_literal			~ '='

:lexeme					~ float				pause => before		event => float

float					~ sign_maybe digit_any '.' digit_many
							| sign_maybe digit_many '.' digit_any

:lexeme					~ generic_id		pause => before		event => generic_id

generic_id_prefix		~ [a-zA-Z\200-\377_]
generic_id_suffix		~ [a-zA-Z\200-\377_0-9]*
generic_id				~ <generic_id_prefix>generic_id_suffix

:lexeme					~ graph_literal		pause => before		event => graph_literal

graph_literal			~ 'graph':i

:lexeme					~ integer			pause => before		event => integer

integer					~ sign_maybe non_zero digit_any
							| zero

non_zero				~ [1-9]

:lexeme					~ open_brace		pause => before		event => open_brace

open_brace				~ '{'

:lexeme					~ open_bracket		pause => before		event => open_bracket

open_bracket			~ '['

semicolon_literal		~ ';'

sign_maybe				~ [+-]
sign_maybe				~

:lexeme					~ strict_literal	pause => before		event => strict_literal

strict_literal			~ 'strict':i

:lexeme					~ string			pause => before		event => string

string					~ string_body

string_body				~ string_char*

string_char				~ [^"] | escaped_quote | escaped_char
escaped_quote			~ '\"'
escaped_char			~ '\' string_char

# Comment with " matching 2nd last \", for the UltraEdit syntax highlighter.

:lexeme					~ subgraph_literal	pause => before		event => subgraph_literal

subgraph_literal		~ 'subgraph':i

zero					~ '0'

# C and C++ comment handling copied from MarpaX::Languages::C::AST.

<C style comment>					~ '/*' <comment interior> '*/'

<comment interior>					~ <optional non stars> <optional star prefixed segments> <optional pre final stars>

<optional non stars>				~ [^*]*
<optional star prefixed segments>	~ <star prefixed segment>*
<star prefixed segment>				~ <stars> [^/*] <optional star free text>
<stars>								~ [*]+
<optional star free text>			~ [^*]*
<optional pre final stars>			~ [*]*

<Cplusplus style comment>			~ '//' <Cplusplus comment interior>
<Cplusplus comment interior>		~ [^\n]*

# Hash comment handling copied from Marpa::R2's metag.bnf.

<hash comment>						~ <terminated hash comment>
										| <unterminated final hash comment>

<terminated hash comment>			~ '#' <hash comment body> <vertical space char>

<unterminated final hash comment>	~ '#' <hash comment body>

<hash comment body>					~ <hash comment char>*

<vertical space char>				~ [\x{A}\x{B}\x{C}\x{D}\x{2028}\x{2029}]

<hash comment char>					~ [^\x{A}\x{B}\x{C}\x{D}\x{2028}\x{2029}]

# White space.

:discard				~ whitespace

whitespace				~ [\s]*

END_OF_GRAMMAR
		})
	);

	$self -> recce
	(
		Marpa::R2::Scanless::R -> new
		({
			grammar          => $self -> grammar,
			#trace_terminals => 99,
		})
	);

	# Since $self -> tree has not been initialized yet,
	# we can't call our _add_daughter() until after this statement.

	$self -> tree(Tree::DAG_Node -> new({name => 'Root', attributes => {uid => 0} }));

	$self -> stack([$self -> tree -> root]);

	for my $name (qw/Prolog Graph/)
	{
		$self -> _add_daughter($name, {});
	}

	# The 'Prolog' daughter is the parent of all items in the prolog,
	# so it gets pushed onto the stack.
	# Later, when 'digraph' or 'graph' is encountered, the 'Graph' daughter replaces it.

	my(@daughters) = $self -> tree -> daughters;
	my($index)     = 0; # 0 => Prolog, 1 => Graph.
	my($stack)     = $self -> stack;

	push @$stack, $daughters[$index];

	$self -> stack($stack);

} # End of BUILD.

# ------------------------------------------------

sub _add_daughter
{
	my($self, $name, $attributes)  = @_;
	$$attributes{uid} = $self -> uid($self -> uid + 1);
	my($node)         = Tree::DAG_Node -> new({name => $name, attributes => $attributes});
	my($stack)        = $self -> stack;

	$$stack[$#$stack] -> add_daughter($node);

} # End of _add_daughter.

# --------------------------------------------------

sub _adjust_edge_attributes
{
	my($self, $mothers) = @_;

	my($attributes);
	my(@daughters);
	my($mother);
	my($name, $next_daughter, $next_name);

	for my $uid (keys %$mothers)
	{
		$mother    = $$mothers{$uid};
		@daughters = $mother -> daughters;

		for my $i (0 .. $#daughters)
		{
			$name = $daughters[$i] -> name;

			if ($name eq 'edge_literal')
			{
				$attributes = $daughters[$i] -> attributes;

				# This test is redundant if we know the input file is syntactally valid,
				# since then there must necessarily be a next daughter after an edge.

				if ($i < $#daughters)
				{
					$next_name = $daughters[$i + 1] -> name;

					if ($next_name =~ /(?:node_(?:|port_|compass_)id)/)
					{
						$daughters[$i] -> set_daughters($daughters[$i + 1] -> clear_daughters);
					}
				}
			}
		}
	}


} # End of _adjust_edge_attributes.

# ------------------------------------------------

sub _attribute_field
{
	my($self, $type, $input) = @_;
	my(@char)          = split(//, $input);
	my($char_count)    = 0;
	my($quote_count)   = 0;
	my($field)         = '';
	my($html)          = 'no';
	my($previous_char) = '';
	my($result)        = '';

	my($char);

	for my $i (0 .. $#char)
	{
		$char_count++;

		$char = $char[$i];
		$html = 'yes' if ( ($html eq 'no') && ($char eq '<') && ($field eq '') );

		$self -> log(debug => "Char: <$char>. HTML: $html. quote_count: $quote_count. Field: $field.");

		if ($char eq '"')
		{
			# Gobble up and escaped quotes.

			if ($previous_char eq '\\')
			{
				$field         .= $char;
				$previous_char = $char;

				next;
			}

			$quote_count++;

			$field .= $char;

			# If HTML, gobble up any quotes.

			if ($html eq 'yes')
			{
				$previous_char = $char;

				next;
			}

			# First quote is start of field.

			if ($quote_count == 1)
			{
				$previous_char = $char;

				next;
			}

			# Second quote is end of field.

			$quote_count = 0;
			$result      = $field;
			$field       = '';

			$self -> log(debug => "Result 1: $result.");

			# Skip the quote, and skip any training '\s=\s'.

			$i++;

			$self -> log(debug => "Input: " . join('', @char[$i .. $#char]) . '.');

			while ( ($i < $#char) && ($char[$i] =~ /[=\s]/) )
			{
				$i++;
				$char_count++;
			}

			$self -> log(debug => "Input: " . join('', @char[$i .. $#char]) . '.');

			last;
		}
		elsif ($quote_count == 0)
		{
			if ($html eq 'no')
			{
				# Discard some chars outside quotes, and possibly finish.

				if ($char =~ /[=\s;,]/)
				{
					next if (length($field) == 0);

					$result = $field;
					$field  = '';

					$self -> log(debug => "Result 2: $result.");

					last;
				}
			}

			$field         .= $char;
			$previous_char = $char;
		}
		else
		{
			$field .= $char;
		}

		$previous_char = $char;
	}

	$result = $field if ($field ne '');
	$result =~ s/^"(.+)"$/$1/;

	$self -> log(debug => "Input 1: $input.");

	$input  = substr($input, $char_count);

	$self -> log(debug => "Input 2: $input.");

	$input  =~ s/^[\s;,]+//;

	$self -> log(debug => "Input 3: $input.");

	return ($result, $input);

} # End of _attribute_field.

# --------------------------------------------------

sub _compress_node_port_compass
{
	my($self, $mothers) = @_;

	# Compress node:port and node:port:compass into 1 node each.
	# These are the possibilities:
	# $i	+ 1		+ 2		+ 3		+ 4
	# Node
	# Node	Colon	Port
	# Node	Colon	Port	Colon	Compass
	#
	# We use a stack so we can reprocess a daughter list after
	# compressing a set of daughters.

	my(@stack) = keys %$mothers;

	my(@daughters);
	my(@edge_daughters);
	my($mother);
	my(@name, $new_name, $node_attributes);

	while (my $uid = shift @stack)
	{
		$mother    = $$mothers{$uid};
		@daughters = $mother -> daughters;

		MIDDLE_LOOP:
		for my $i (0 .. $#daughters)
		{
			# We try the longest possible match first, since the alternative
			# would accidently find the first part of the longest match.

			for (my $offset = 4; $offset > 0; $offset -= 2)
			{
				if ( ($i + $offset) <= $#daughters)
				{
					if ($self -> _compress_nodes($mothers, $uid, \@daughters, $i, $offset) )
					{
						# Reprocess the mother's daughters after compressing ($offset + 1) nodes.

						unshift @stack, $uid;

						# I hate jumps, but I need to exit these 2 loops immediately,
						# since the mother's daughter list has just been fiddled.

						last MIDDLE_LOOP;
					}
				}
			}
		}
	}

} # End of _compress_node_port_compass.

# -----------------------------------------------

sub _compress_nodes
{
	my($self, $mothers, $uid, $daughters, $i, $offset) = @_;
	my($found) = 0;

	my(@name);

	$name[0] = $$daughters[$i + 1] -> name;
	$name[1] = ($offset == 4) ? $$daughters[$i + 3] -> name : 'colon';

	if ("$name[0]$name[1]" eq 'coloncolon')
	{
		# Preserve the attributes of the last node, since they belong to the edge.
		# Here we attach them to the new node which is a combination of several nodes.
		# Later, the caller of compress_node_port_compass() will move them back to the edge.

		my(@edge_daughters) = ( ($i + $offset) <= $#$daughters) ? $$daughters[$i + $offset] -> daughters : ();
		$found              = 1;
		my($new_name)       = '';

		my($node_attributes);

		for (my $j = $i; $j <= ($i + $offset); $j++)
		{
			$node_attributes  = $$daughters[$j] -> attributes;
			$new_name        .= $$node_attributes{value};
		}

		splice(@$daughters, ($i + 1), $offset);

		# We update the attributes with the node's real name.
		# The tree node's name will still be 'node_id'.

		$node_attributes         = $$daughters[$i] -> attributes;
		$$node_attributes{value} = $new_name;

		$$daughters[$i] -> attributes($node_attributes);
		$$daughters[$i] -> set_daughters(@edge_daughters) if ($#edge_daughters >= 0);
		$$mothers{$uid} -> set_daughters(@$daughters);
	}

	return $found;

} # End of _compress_nodes;

# -----------------------------------------------
# The special case is <<...>>, as used in attributes.

sub _find_terminator
{
	my($self, $stringref, $start) = @_;
	my(@char)   = split(//, substr($$stringref, $start) );
	my($offset) = 0;
	my($quote)  = '';
	my($angle)  = 0; # Set to 1 if inside <<...>>.

	my($char);

	for my $i (0 .. $#char)
	{
		$char   = $char[$i];
		$offset = $i;

		if ($quote)
		{
			# Ignore an escaped quote.
			# The first few backslashes are just to fix syntax highlighting in UltraEdit.

			next if ( ($char =~ /[\]\"\'>]/) && ($i > 0) && ($char[$i - 1] eq '\\') );

			# Get out of quotes if matching one found.

			if ($char eq $quote)
			{
				if ($quote eq '>')
				{
					$quote = '' if (! $angle || ($char[$i - 1] eq '>') );

					next;
				}

				$quote = '';

				next;
			}
		}
		else
		{
			# Look for quotes.
			# 1: Skip escaped chars.

			next if ( ($i > 0) && ($char[$i - 1] eq '\\') );

			# 2: " and '.
			# The backslashes are just to fix syntax highlighting in UltraEdit.

			if ($char =~ /[\"\']/)
			{
				$quote = $char;

				next;
			}

			# 3: <.
			# In the case of attributes but not nodes names, quotes can be <...> or <<...>>.

			if ($char =~ '<')
			{
				$quote = '>';
				$angle = 1 if ( ($i < $#char) && ($char[$i + 1] eq '<') );

				next;
			}

			last if ($char eq ']');
		}
	}

	return $start + $offset;

} # End of _find_terminator.

# --------------------------------------------------

sub log
{
	my($self, $level, $s) = @_;

	$self -> logger -> log($level => $s) if ($self -> logger);

} # End of log.

# --------------------------------------------------

sub _post_process
{
	my($self) = @_;

	# Walk the tree, find the edges, and then stockpile their mothers.
	# Later, compress the [node]:[port]:[compass] quintuplets and the
	# [node]:[port] triplets each into a single node, either [node:port:compass]
	# or [node:port].
	# The Tree::DAG_Node docs warn against modifying the tree during a walk,
	# so we use a hash to track all the mothers found, and post-process them.

	my(%mothers);

	$self -> tree -> walk_down
	({
		callback => sub
		{
			my($node) = @_;
			my($name) = $node -> name;

			if ($name eq 'edge_literal')
			{
				my($attributes)  = $node -> mother -> attributes;
				my($uid)         = $$attributes{uid};
				$mothers{$uid}   = $node -> mother if (! $mothers{$uid});
			}

			# Keep recursing.

			return 1;
		},
		_depth => 0,
	});

	$self -> _compress_node_port_compass(\%mothers);

	# Now look for edges hanging off the edge's head node/subgraph,
	# and move them back to belong to the edge itself.

	$self -> _adjust_edge_attributes(\%mothers);

} # End of _post_process.

# --------------------------------------------------

sub _process
{
	my($self)          = @_;
	my($string)        = $self -> graph_text;
	my($length)        = length $string;
	my($digraph_graph) = qr/(?:digraph_literal|graph_literal)/;
	my($simple_token)  = qr/(?:colon|comma|edge_literal|float|integer|node_port|strict_literal|subgraph_literal)/;

	$self -> log(debug => "Input:\n$string");

	# We use read()/lexeme_read()/resume() because we pause at each lexeme.

	my($attribute_list, $attribute_value);
	my(@event, $event_name);
	my($generic_id);
	my($lexeme_name, $lexeme, $literal);
	my($span, $start, $s);
	my($type);

	for
	(
		my $pos = $self -> recce -> read(\$string);
		$pos < $length;
		$pos = $self -> recce -> resume($pos)
	)
	{
		$self -> log(debug => "read() => pos: $pos. ");

		@event          = @{$self -> recce -> events};
		$event_name     = ${$event[0]}[0];
		($start, $span) = $self -> recce -> pause_span;
		$lexeme_name    = $self -> recce -> pause_lexeme;
		$lexeme         = $self -> recce -> literal($start, $span);

		$self -> log(debug => "pause_span($lexeme_name) => start: $start. span: $span. " .
			"lexeme: $lexeme. event: $event_name. ");

		if ($event_name =~ $simple_token)
		{
			$pos = $self -> _process_lexeme(\$string, $start, $event_name, $lexeme_name);
		}
		elsif ($event_name eq 'close_brace')
		{
			$pos     = $self -> recce -> lexeme_read($lexeme_name);
			$literal = substr($string, $start, $pos - $start);

			$self -> log(debug => "close_brace => '$literal'");
			$self -> _process_brace($literal);
		}
		elsif ($event_name eq 'close_bracket')
		{
			$pos     = $self -> recce -> lexeme_read($lexeme_name);
			$literal = substr($string, $start, $pos - $start);

			$self -> log(debug => "close_bracket => '$literal'");
			$self -> _process_bracket($literal);
		}
		elsif ($event_name eq 'generic_id')
		{
			$pos        = $self -> recce -> lexeme_read($lexeme_name);
			$generic_id = substr($string, $start, $pos - $start);
			$type       = 'node_id';

			if ($generic_id =~ /^(?:graph|node|edge)$/i)
			{
				$type = 'class';
			}
			elsif ($generic_id eq 'subgraph')
			{
				$type = 'literal';
			}

			$self -> log(debug => "generic_id => '$generic_id'. type => $type");
			$self -> _process_token($type, $generic_id);
		}
		elsif ($event_name eq 'open_brace')
		{
			$pos     = $self -> recce -> lexeme_read($lexeme_name);
			$literal = substr($string, $start, $pos - $start);

			$self -> log(debug => "open_brace => '$literal'");
			$self -> _process_brace($literal);
		}
		elsif ($event_name eq 'open_bracket')
		{
			$pos     = $self -> recce -> lexeme_read($lexeme_name);
			$literal = substr($string, $start, $pos - $start);

			$self -> log(debug => "open_bracket => '$literal'");
			$self -> _process_bracket($literal);

			$pos = $self -> _find_terminator(\$string, $start);

			$attribute_list = substr($string, $start + 1, $pos - $start - 1);

			$self -> log(debug => "index() => attribute list: $attribute_list");
			$self -> _process_attributes($attribute_list);
		}
		elsif ($event_name eq 'string')
		{
			$pos     = $self -> recce -> lexeme_read($lexeme_name);
			$literal = substr($string, $start, $pos - $start);

			$self -> log(debug => "string => '$literal'");
			$self -> _process_token($event_name, $literal);
		}
		# From here on are the low-frequency events.
		elsif ($event_name =~ $digraph_graph)
		{
			$pos     = $self -> recce -> lexeme_read($lexeme_name);
			$literal = substr($string, $start, $pos - $start);

			$self -> log(debug => "$event_name => '$literal'");
			$self -> _process_digraph_graph($event_name, $literal);
		}
		elsif ($event_name eq 'equals_literal')
		{
			$pos = $self -> _process_lexeme(\$string, $start, $event_name, $lexeme_name);
		}
		else
		{
			die "Unexpected lexeme '$lexeme_name' with a pause\n";
		}
    }

	# Return a defined value for success and undef for failure.

	return $self -> recce -> value;

} # End of _process.

# --------------------------------------------------

sub _process_attributes
{
	my($self, $attribute_list) = @_;

	my($name);
	my($value);

	while (length($attribute_list) > 0)
	{
		($name, $attribute_list)  = $self -> _attribute_field('name', $attribute_list);
		($value, $attribute_list) = $self -> _attribute_field('value', $attribute_list);

		$self -> _add_daughter('attribute', {type => $name, value => $value});

		# Discard attribute teminators.

		while ($attribute_list =~ /^[;,]/)
		{
			substr($attribute_list, 0, 1) = '';
		}
	}

} # End of _process_attributes.

# --------------------------------------------------

sub _process_brace
{
	my($self, $name) = @_;

	# When the 1st '{' is encountered, the 'Graph' daughter of the root
	# becomes the parent of all other tree nodes, replacing the 'Prolog' daughter.

	if ($self -> brace_count == 0)
	{
		my($stack) = $self -> stack;

		pop @$stack;

		my(@daughters) = $self -> tree -> daughters;
		my($index)     = 1; # 0 => Prolog, 1 => Graph.

		push @$stack, $daughters[$index];

		$self -> stack($stack);
	}

	# When a '{' is encountered, the last thing pushed becomes it's parent.
	# Likewise, when a '}' is encountered, we pop the stack.

	my($stack) = $self -> stack;

	if ($name eq '{')
	{
		$self -> brace_count($self -> brace_count + 1);
		$self -> _add_daughter($name, {value => $name});

		my(@daughters) = $$stack[$#$stack] -> daughters;

		push @$stack, $daughters[$#daughters];
	}
	else
	{
		pop @$stack;

		$self -> stack($stack);
		$self -> _add_daughter($name, {value => $name});
		$self -> brace_count($self -> brace_count - 1);
	}

} # End of _process_brace.

# --------------------------------------------------

sub _process_bracket
{
	my($self, $name) = @_;

	# When a '[' is encountered, the last thing pushed becomes it's parent.
	# Likewise, if ']' is encountered, we pop the stack.

	my($stack) = $self -> stack;

	if ($name eq '[')
	{
		my(@daughters) = $$stack[$#$stack] -> daughters;

		push @$stack, $daughters[$#daughters];
	}
	else
	{
		pop @$stack;

		$self -> stack($stack);
	}

} # End of _process_bracket.

# --------------------------------------------------

sub _process_digraph_graph
{
	my($self, $name, $value) = @_;

	$self -> _add_daughter($name, {value => $value});

	# When 'digraph' or 'graph' is encountered, the 'Graph' daughter of the root
	# becomes the parent of all other tree nodes, replacing the 'Prolog' daughter.

	my($stack) = $self -> stack;

	pop @$stack;

	my(@daughters) = $self -> tree -> daughters;
	my($index)     = 1; # 0 => Prolog, 1 => Graph.

	push @$stack, $daughters[$index];

	$self -> stack($stack);

} # End of _process_digraph_graph.

# --------------------------------------------------

sub _process_lexeme
{
	my($self, $string, $start, $event_name, $lexeme_name) = @_;
	my($pos)   = $self -> recce -> lexeme_read($lexeme_name);
	my($value) = substr($$string, $start, $pos - $start);

	$self -> log(debug => "$event_name => '$value'");
	$self -> _process_token($event_name, $value);

	return $pos;

} # End of _process_lexeme.

# --------------------------------------------------

sub _process_token
{
	my($self, $name, $value) = @_;

	$self -> _add_daughter($name, {value => $value});

} # End of _process_token.

# --------------------------------------------------

sub run
{
	my($self) = @_;

	if ($self -> description)
	{
		# Assume graph is a single line without comments.

		$self -> graph_text($self -> description);
	}
	elsif ($self -> input_file)
	{
		$self -> graph_text
					(
						scalar
						read_file
						(
							$self -> input_file,
							binmode => ':encoding(UTF-8)',
						)
					);
	}
	else
	{
		die "Error: You must provide a graph using one of -input_file or -description\n";
	}

	# Return 0 for success and 1 for failure.

	my($result) = 0;

	try
	{
		if (defined $self -> _process)
		{
			$self -> _post_process;
			$self -> log(debug => join("\n", @{$self -> tree -> tree2string}) );
		}
		else
		{
			$result = 1;
		}
	}
	catch
	{
		$result = 1;

		$self -> log(error => "Exception: $_");
	};

	if ($result == 0)
	{
		# Clean up the stack by popping the Root.

		my($stack) = $self -> stack;

		pop @$stack;

		$self -> stack($stack);
		$self -> log(debug => 'Brace count:  ' . $self -> brace_count . ' (0 expected)');
		$self -> log(debug => 'Stack size:   ' . $#{$self -> stack} . ' (0 expected)');

		my($output_file) = $self -> output_file;

		if ($output_file)
		{
			$self -> renderer
			(
				GraphViz2::Marpa::Renderer::GraphViz2 -> new
				(
					logger      => $self -> logger,
					maxlevel    => $self -> maxlevel,
					minlevel    => $self -> minlevel,
					output_file => $self -> output_file,
					tree        => $self -> tree,
				)
			);

			$self -> renderer -> run;
		}
	}

	# Return 0 for success and 1 for failure.

	$self -> log(debug => "Parse result: $result (0 is success)");

	return $result;

} # End of run.

# --------------------------------------------------

1;

=pod

=head1 NAME

GraphViz2::Marpa - A Marpa-based parser for Graphviz dot files

=head1 Synopsis

=over 4

=item o Display help

	perl scripts/g2m.pl   -h

=item o Run the parser without running the default renderer

	perl scripts/parse.pl -lexed_file x.lex -parsed_file x.parse

	x.parse will be a CSV file of parsed tokens.

=item o Run the parser and the default renderer

	perl scripts/parse.pl -lexed_file x.lex -parsed_file x.parse -output_file x.rend

	x.rend will be a Graphviz dot file.

=back

See also L</Scripts>.

=head1 Description

L<GraphViz2::Marpa> provides a L<Marpa::R2>-based parser for L<Graphviz|http://www.graphviz.org/> (dot) graph definitions.

Demo output: L<http://savage.net.au/Perl-modules/html/graphviz2.marpa/index.html>.

L<Marpa's homepage|http://savage.net.au/Marpa.html>.

The Marpa grammar as an image: L<http://savage.net.au/Ron/html/graphviz2.marpa/Marpa.Grammar.svg>. This image was created
with L<Graphviz|http://www.graphviz.org/> via L<GraphViz2>.

=head1 Modules

=over 4

=item o L<GraphViz2::Marpa>

The current module, which documents the set of modules.

It uses L<GraphViz2::Marpa::Lexer> and L<GraphViz2::Marpa::Parser>. The latter can, optionally, use the default renderer L<GraphViz2::Marpa::Renderer::GraphViz2>.

See scripts/g2m.pl.

=item o L<GraphViz2::Marpa::Lexer>

The lexer. The real work is done by L<GraphViz2::Marpa::Lexer::DFA>.

Processes a L<Graphviz|http://www.graphviz.org/> (dot) graph definition and builds a data structure representing the lexed graph. It can output that data, via RAM or a CSV file,
which can then be read by the parser L<GraphViz2::Marpa::Parser>.

See scripts/lex.pl and scripts/g2m.pl.

=item o L<GraphViz2::Marpa::Lexer::DFA>

Called by L<GraphViz2::Marpa::Lexer> to run the DFA (Discrete Finite Automaton).

Wraps L<Set::FA::Element>, which is what actually lexes the input L<Graphviz|http://www.graphviz.org/> (dot) graph definition.

=item o L<GraphViz2::Marpa::Parser>

The parser. Accepts a L<Graphviz|http://www.graphviz.org/> (dot) graph definition in the lexed format and builds a similar data structure representing the parsed graph.
It can output that data, via RAM or a CSV file, which can then be read by the default renderer, L<GraphViz2::Marpa::Renderer::GraphViz2>.

See scripts/parse.pl and scripts/g2m.pl.

=item o L<GraphViz2::Marpa::Renderer::GraphViz2>

The default renderer. Optionally called by the parser.

=item o L<GraphViz2::Marpa::Utils>

Auxiliary code.

=back

=head1 Sample Data

=over 4

=item o Input files: data/*.gv

These are L<Graphviz|http://www.graphviz.org/> (dot) graph definition files.

Note 1: Some data/*.gv files contain I<serious> deliberate mistakes (from the point of view of L<Graphviz|http://www.graphviz.org/>), but they helped with writing the code.

Specifically, they are data/(01, 02, 03, 04, 05, 06, 08).gv. Natually, they do not produce output files data/*.lex, data/*.parse, data/*.rend or html/*.svg.

Note 2: Some data/*.gv files contain I<slight> deliberate mistakes, which do not stop production of output files. They do, however, cause various warning messages to be printed
when certain scripts are run.

=item o Output files: data/*.lex, data/*.parse, data/*.rend and html/*.svg

The data/*.lex and data/*.parse are CSV files.

The data/*.rend are L<Graphviz|http://www.graphviz.org/> (dot) graph definition files output by the default renderer.

The round trip shows that the lex/parse process does not lose information along the way, but comments are discarded. See L<GraphViz2::Marpa::Lexer/How does the lexer handle comments?>.

The html/*.svg files are output by 'dot'.

=item o Data for the State Transition Table

See data/stt.csv (CSV file) and html/stt.html.

Also, data/stt.csv has been incorporated into the source code of L<GraphViz2::Marpa::Lexer>.

The CSV file was converted to HTML with scripts/stt2html.pl.

=item o Documentation for the command line options and object attributes

See data/code.attributes.csv (CSV file) and data/code.attributes.html.

The CSV file was converted to HTML with scripts/code.attributes2html.pl.

=back

=head1 Scripts

These are in the scripts/ directory.

=over 4

=item o code.attributes2html.pl

Generate both data/code.attributes.csv and data/code.attributes.html.

=item o dot2lex.pl

Convert all data/*.gv files to data/*.lex using lex.pl.

=item o dot2rend.pl

Convert all data/*.gv files to data/*.lex and data/*.parse and data/*.rend using lex.pl and parse.pl.

=item o find.config.pl

Print the path to the config file, as determined by L<File::ShareDir>'s dist_file().

=item o g2m.pl

Run the lexer, and then run the parser on the output of the lexer. Try running with -h.

=item o g2m.sh

Simplifies running g2m.pl.

=item o generate.demo.sh

Runs dot2rend.pl, rend2svg.pl and generate.index.pl.

Then runs code.attributes2html.pl and stt2html.pl.

Then it copies html/*.html and html/*.svg to my web server's doc root, $DR/Perl-modules/html/graphviz2.marpa/.

=item o generate.index.pl

Generates html/index.html from data/*.gv and html/*.svg.

=item o lex.1.sh

Simplifies running lex.sh.

=item o lex.parse.sh

Simplifies running g2m.sh, and ensures the *.svg version of the tested data file is up-to-date.

=item o lex.pl

Run the lexer. Try running with -h.

=item o lex.sh

Simplifies running lex.pl.

=item o lex2parse.pl

Convert all data/*.lex to data/*.parse using parse.pl.

=item o lex2rend.pl

Convert all data/*.lex to data/*.parse and data/*.rend using parse.pl.

=item o parse.1.sh

Simplifies running parse.sh.

=item o parse.pl

Run the parser. Try running with -h.

=item o parse.sh

Simplifies running parse.pl.

=item o parse2rend.pl

Convert all data/*.parse to data/*.rend using rend.pl.

=item o pod2html.sh

Converts all *.pm files to *.html, and copies them in my web server's dir structure.

=item o rend.1.sh

Simplifies running read.sh.

=item o rend.pl Try running with -h.

Run the default renderer.

=item o rend.sh

Simplifies running rend.pl.

=item o rend2svg.pl

Convert all data/*.rend to html/*.svg using dot.

=item o stt2html.pl

Convert data/stt.csv to html/stt.html.

=back

=head1 Distributions

This module is available as a Unix-style distro (*.tgz).

See L<http://savage.net.au/Perl-modules/html/installing-a-module.html>
for help on unpacking and installing distros.

=head1 Installation

Install L<GraphViz2::Marpa> as you would for any C<Perl> module:

Run:

	cpanm GraphViz2::Marpa

or run:

	sudo cpan GraphViz2::Marpa

or unpack the distro, and then either:

	perl Build.PL
	./Build
	./Build test
	sudo ./Build install

or:

	perl Makefile.PL
	make (or dmake or nmake)
	make test
	make install

=head1 Constructor and Initialization

C<new()> is called as C<< my($g2m) = GraphViz2::Marpa -> new(k1 => v1, k2 => v2, ...) >>.

It returns a new object of type C<GraphViz2::Marpa>.

Key-value pairs accepted in the parameter list (see corresponding methods for details
[e.g. L<description([$graph])>]):

=over 4

=item o description => $graphDescription

Read the L<Graphviz|http://www.graphviz.org/> (dot) graph definition from the command line.

You are strongly encouraged to surround this string with '...' to protect it from your shell.

See also the 'input_file' option to read the description from a file.

The 'description' option takes precedence over the 'input_file' option.

Default: ''.

=item o input_file => $aDotInputFileName

Read the L<Graphviz|http://www.graphviz.org/> (dot) graph definition from a file.

See also the 'description' option to read the graph definition from the command line.

The 'description' option takes precedence over the 'input_file' option.

Default: ''.

See the distro for data/*.gv.

=item o lexed_file => $aLexedOutputFileName

Specify the name of a CSV file of lexed tokens for the lexer to write. This file can be input to the parser.

Default: ''.

The default means the file is not written.

See the distro for data/*.lex.

=item o logger => $aLoggerObject

Specify a logger compatible with L<Log::Handler>, for the lexer and parser to use.

Default: A logger of type L<Log::Handler> which writes to the screen.

To disable logging, just set 'logger' to the empty string (not undef).

=item o maxlevel => $logOption1

This option affects L<Log::Handler>.

See the L<Log::Handler::Levels> docs.

Default: 'notice'.

=item o minlevel => $logOption2

This option affects L<Log::Handler>.

See the L<Log::Handler::Levels> docs.

Default: 'error'.

No lower levels are used.

=item o output_file => aRenderedOutputFileName

Specify the name of a file for the renderer to write.

Default: ''.

The default means the renderer is not called.

=item o parsed_file => aParsedOutputFileName

Specify the name of a CSV file of parsed tokens for the parser to write. This file can be input to the renderer.

Default: ''.

The default means the file is not written.

=item o renderer => $aRendererObject

Specify a renderer for the parser to use.

Default: undef.

=item o report_forest => $Boolean

Log the forest of paths recognised by the parser.

Default: 0.

=item o report_items => $Boolean

Log the items recognised by the lexer.

Default: 0.

=item o report_stt => $Boolean

Log the State Transition Table.

Calls L<Set::FA::Element/report()>. Set min and max log levels to 'info' for this.

Default: 0.

=item o stt_file => $sttFileName

Specify which file contains the State Transition Table.

Default: ''.

The default value means the STT is read from the source code of L<GraphViz2::Marpa::Lexer>.

Candidate files are '' and 'data/stt.csv'.

The type of this file must be specified by the 'type' option.

If the file name matches /csv$/, the value of the 'type' option is set to 'csv'.

=item o timeout => $seconds

Run the DFA for at most this many seconds.

Default: 10.

=item o type => $type

Specify the type of the stt_file: '' for internal STT and 'csv' for CSV.

Default: ''.

The default value means the STT is read from the source code of L<GraphViz2::Marpa::Lexer>.

This option must be used with the 'stt_file' option.

Warning: The 'ods' option is disabled, because I can find no way in LibreOffice to make it operate in ASCII. What happens is that when you type "
(i.e. the double-quote character on the keyboard), LibreOffice inserts a different double-quote character, which, when exported as CSV in Unicode
format, produces these 3 bytes: 0xe2, 0x80, 0x9c. This means that if you edit the STT, you absolutely must export to a CSV file in ASCII format.
It also means that dot identifiers in (normal) double-quotes will never match the double-quotes in the *.ods file.

=back

=head1 Methods

=head2 description([$graph])

The [] indicate an optional parameter.

Get or set the L<Graphviz|http://www.graphviz.org/> (dot) graph definition string.

The value supplied by the 'description' option takes precedence over the value read from the 'input_file'.

See also L</input_file()>.

'description' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 input_file([$graph_file_name])

Here, the [] indicate an optional parameter.

Get or set the name of the file to read the L<Graphviz|http://www.graphviz.org/> (dot) graph definition from.

The value supplied by the 'description' option takes precedence over the value read from the 'input_file'.

See also the L</description()> method.

'input_file' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 lexed_file([$lex_file_name])

Here, the [] indicate an optional parameter.

Get or set the name of the CSV file of lexed tokens for the lexer to write. This file can be input to the parser.

'lexed_file' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 logger([$logger_object])

Here, the [] indicate an optional parameter.

Get or set the logger object.

To disable logging, just set 'logger' to the empty string (not undef), in the call to L</new()>.

This logger is passed to other modules.

'logger' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 maxlevel([$string])

Here, the [] indicate an optional parameter.

Get or set the value used by the logger object.

This option is only used if L<GraphViz2::Marpa:::Lexer> or L<GraphViz2::Marpa::Parser>
use or create an object of type L<Log::Handler>. See L<Log::Handler::Levels>.

'maxlevel' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 minlevel([$string])

Here, the [] indicate an optional parameter.

Get or set the value used by the logger object.

This option is only used if L<GraphViz2::Marpa:::Lexer> or L<GraphViz2::Marpa::Parser>
use or create an object of type L<Log::Handler>. See L<Log::Handler::Levels>.

'minlevel' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 new()

See L</Constructor and Initialization> for details on the parameters accepted by L</new()>.

=head2 output_file([$file_name])

Here, the [] indicate an optional parameter.

Get or set the name of the file for the renderer to write.

'output_file' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 parsed_file([$file_name])

Here, the [] indicate an optional parameter.

Get or set the name of the file of parsed tokens for the parser to write. This file can be input to the renderer.

'parsed_file' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 renderer([$renderer_object])

Here, the [] indicate an optional parameter.

Get or set the renderer object.

This renderer is passed to L<GraphViz2::Marpa::Parser>.

'renderer' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 report_forest([$Boolean])

The [] indicate an optional parameter.

Get or set the value which determines whether or not to log the forest of paths recognised by the parser.

'report_forest' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 report_items([$Boolean])

The [] indicate an optional parameter.

Get or set the value which determines whether or not to log the items recognised by the lexer and parser.

'report_items' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 report_stt([$Boolean])

The [] indicate an optional parameter.

Get or set the value which determines whether or not to log the parsed state transition table (STT).

'report_stt' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 run()

This is the only method the caller needs to call. All parameters are supplied to L</new()> (or other methods).

Returns 0 for success and 1 for failure.

=head2 stt_file([$stt_file_name])

The [] indicate an optional parameter.

Get or set the name of the file containing the State Transition Table.

This option is used in conjunction with the 'type' option to L</new()>.

If the file name matches /csv$/, the value of the 'type' option is set to 'csv'.

'stt_file' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 timeout($seconds)

The [] indicate an optional parameter.

Get or set the timeout for how long to run the DFA and the Parser.

'timeout' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head2 type([$type])

The [] indicate an optional parameter.

Get or set the value which determines what type of 'stt_file' is read.

'type' is a parameter to L</new()>. See L</Constructor and Initialization> for details.

=head1 FAQ

The lexer and the parser each has an FAQ: L<Lexer|GraphViz2::Marpa::Lexer/FAQ>, and L<Parser|GraphViz2::Marpa::Parser/FAQ>.

=head2 What is the homepage of Marpa?

L<http://jeffreykegler.github.com/Marpa-web-site/>.

=head2 Why do I get error messages like the following?

	Error: <stdin>:1: syntax error near line 1
	context: digraph >>>  Graph <<<  {

Graphviz reserves some words as keywords, meaning they can't be used as an ID, e.g. for the name of the graph.
So, don't do this:

	strict graph graph{...}
	strict graph Graph{...}
	strict graph strict{...}
	etc...

Likewise for non-strict graphs, and digraphs. You can however add double-quotes around such reserved words:

	strict graph "graph"{...}

Even better, use a more meaningful name for your graph...

The keywords are: node, edge, graph, digraph, subgraph and strict. Compass points are not keywords.

See L<keywords|http://www.graphviz.org/content/dot-language> in the discussion of the syntax of DOT
for details.

=head2 Does this package support Unicode in the input dot file?

No. Sorry. Not yet.

=head2 How can I switch from Marpa::XS to Marpa::PP?

Install Marpa::PP manually. It is not mentioned in Build.PL or Makefile.PL.

Patch GraphViz2::Marpa::Parser (line 15) from Marpa::XS to Marpa:PP.

Then, run the tests which ship with this module. I've tried this, and the tests all worked. You don't need to install the code to test it. Just use:

	shell> cd GraphViz2-Marpa-1.00/
	shell> prove -Ilib -v t

=head2 If I input x.gv and output x.rend, should these 2 files be identical?

Yes - at least in the sense that running dot with them as input will produce the same output files. This is using the default renderer, of course.

Since comments in *.gv files are discarded, they can never be in the output files (*.lex, *.parse and *.rend).

So, if x.gv is formatted as I do, then x.rend will be formatted identically.

=head2 Why does the report_items option output 2 copies of the tokens?

Because the 1st copy is printed by the lexer and the 2nd by the parser.

=head2 How are custom graph attributes handled?

They are not handled at all. Sorry. The lexer only supports attributes defined by Graphviz itself.

=head2 How are the demo files generated?

I run:

	shell> scripts/generate.demo.sh

Which runs these:

	shell> perl scripts/dot2rend.pl
	shell> perl scripts/rend2svg.pl
	shell> perl scripts/generate.index.pl

And copies the demo files to my dev machine's doc root:

	shell> cp html/*.html html/*.svg $DR/Perl-modules/html/graphviz2.marpa/

=head1 Machine-Readable Change Log

The file CHANGES was converted into Changelog.ini by L<Module::Metadata::Changes>.

=head1 Version Numbers

Version numbers < 1.00 represent development versions. From 1.00 up, they are production versions.

=head1 Thanks

Many thanks are due to the people who worked on L<Graphviz|http://www.graphviz.org/>.

Jeffrey Kegler wrote L<Marpa::XS>, and has a blog on it at L<http://blogs.perl.org/users/jeffrey_kegler/>.

=head1 Support

Email the author, or log a bug on RT:

L<https://rt.cpan.org/Public/Dist/Display.html?Name=GraphViz2::Marpa>.

=head1 Author

L<GraphViz2::Marpa> was written by Ron Savage I<E<lt>ron@savage.net.auE<gt>> in 2012.

Home page: L<http://savage.net.au/index.html>.

=head1 Copyright

Australian copyright (c) 2012, Ron Savage.

	All Programs of mine are 'OSI Certified Open Source Software';
	you can redistribute them and/or modify them under the terms of
	The Artistic License, a copy of which is available at:
	http://www.opensource.org/licenses/index.html

=cut
