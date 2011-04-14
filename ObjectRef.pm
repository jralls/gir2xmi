#!/usr/bin/perl -w
#-*- mode: perl; -*-
use strict;
=head1 NAME

ObjectRef

=head1 DESCRIPTION

ObjectRef is part of gir2xmi. It generates somewhat random ids for objects and keeps track of them in a hash reference. XMI uses the ids for references to the original objects in a variety of ways.

=cut
package ObjectRef;

use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use Carp qw(cluck carp croak confess);

our $curl = "http://www.gtk.org/introspection/c/1.0";
our $global;

=head3 new

Returns a new ObjectRef object

=cut
sub new {
    my ($c_name) = @_;
    my $class = ref($c_name) || $c_name;
    my $self = {};
    $$self{aliases} = {};
    bless $self, $class;
    return $self;
}

=head3 set_global

Sets the calling object as the global object. References which are
"left over" at the end of processing a gir namespace are transferred
to the global object, and references to the same name in future
namespaces will get the global object id.

=cut
sub set_global {
    $global = shift;
}

=head3 global

Return the global object.

=cut
sub global {
    return $global;
}

=head3 is_global

Test if the calling object is global. Needed to prevent infinite recursion.

=cut
sub is_global {
    my $self = shift;
    return $self == $global;
}

=head3 exists

Check if a particular name has been registered either in the current
or the global registry object.

=cut
sub exists {
    my ($self, $name) = @_;
    return 0 unless $name;
#    warn "$name exists in registry" if exists $$self{name};
#    warn "$name is an alias for $$self{aliases}{$name}"
#	if exists $$self{aliases}{$name};
    my $exists = (exists $$self{$name} ||
		  exists $$self{aliases}{$name} &&
		  exists $$self{$$self{aliases}{$name}});

    return $global->exists($name) unless $exists || $self == $global;
    return $exists;
}

=head3 make_id

Make a unique id, combining an item name with a qualifier and adding
the current time-value as a seed, then pushing it through MD5 to make
a nice identifier.

=cut
sub make_id {
    my ($self, $name, $qualifier) = @_;
    die "Can't make an id with no name" unless $name;
    my $salt = rand();
    $qualifier = "foo" unless $qualifier;
    return md5_hex("$qualifier.$name.$salt");
}

=head3 register_object(type, name, real)

Create a new object in the current registry unless one of the same
name already exists, either in the current or global
registries. Returns the id of the object. The type is passed as the
qualifier argument to make_id, and is recorded for later testing. The
last argument, real, is used to indicate that the method has been
called when an object is created and therefore that the object is
"realized" in the UML model.

=cut
sub register_object {
    my ($self, $type, $name, $real) = @_;
#    $self->debug(Data::Dumper->Dump([$self], ["ObjectRef"])) if $debug > 5;
    die "Can't make an id with no name" unless $name;
    cluck "Can't make an id with no type" unless $type;
    $$self{$name} = {} unless exists $$self{$name};
    my $entry = $$self{$name};
    if ($$entry{type} && $$entry{type} ne $type &&
	$$entry{type} ne "Temporary") {
	cluck ("Attempt to register existing object $$entry{type}:$name with new type $type");
	return $$entry{id};
    }
    $$entry{real} = $$entry{real} || $real ? 1 : 0;
    $$entry{type} = $type ? $type : "Temporary";
    $$entry{id} = $self->make_id($name, $type) unless $$entry{id};

    return $$entry{id};
}

=head3 object_id(type, name)

Return the object_id of the named object if it has been registered,
checking aliases and names in both the calling and global
registries. If the named object isn't registered, object_id will
create a "dummy" registration (the real argument to register_object is
false).

=cut
sub object_id {
    my ($self, $type, $name) = @_;
    die "No $self" unless $self;
    die "Aliases not initialized" unless exists $$self{aliases};
    cluck "No name passed in to object_id" unless $name;

    $name = $$self{aliases}{$name} if exists $$self{aliases}{$name};
    if (exists $$self{$name}) {
	return $$self{$name}{id};
    }
    return $global->object_id($type, $name) if $global->exists($name);
    return $self->register_object($type, $name);
}

=head3 object_type(name)

Return the type registered with name, or undef if it isn't found. Checks aliases and both the calling and global registries.

=cut
sub object_type {
    my ($self, $name) = @_;
    return undef unless $name;
    $name = $$self{aliases}{$name} if exists $$self{aliases}{$name};
    return $global->object_type($name)
	unless exists $$self{$name} || $self == $global;
    return undef unless exists $$self{$name};
    return $$self{$name}{type};
}

=head3 register_alias(gir_type_element)

Makes an alias of an element having two attributes, name and c:type. There are two elements in gir use these attributes this way, alias (representing a C typedef statement) and type (used to designate the type of function parameters and class member variables.

=cut
sub register_alias {
    my ($self, $element) = @_;
    my $name = $element->getAttribute("name") or return;
    my $typeattr = $element->getAttributeNS($curl, "type") or return;

    $$self{aliases}{$typeattr} = $name;
}

=head3 get_unregistered

Returns a list reference of all registrations in the calling registry whose "real" value is false. This can be used to create new DataType elements for generic types.

=cut
sub get_unregistered {
    my ($self) = @_;
    my $list = [];
    foreach my $name (keys %$self) {
	next if $$self{$name}{real};
	next if $name eq "aliases";
	my $hash = $$self{$name};
	$$hash{name} = $name;
	push @$list, $hash;
    }
    return $list;
}

=head3 reregister_global(name)

Moves a registration and all of its aliases from the calling registry
to the global one, first checking to ensure that neither any of the
aliases nor the named item are alredy registered in the global
registry.

=cut
sub reregister_global {
    my ($self, $name) = @_;
    croak "Don't call reregister_global on global" if $global == $self;
    croak "$name already registered in global" if $global->exists($name);
    if (exists $$self{aliases}{$name}) {
	$name = $$self{aliases}{$name};
	croak "Real name $name already exists in global, aliased by $name"
	    if $global->exists($name);
    }
    $$global{$name} = $$self{$name};
    delete $$self{$name};
    my @aliases;
    for my $alias (keys %{$$self{aliases}}) {
	push @aliases, $alias if $$self{aliases}{$alias} eq $name;
    }
    for my $alias (@aliases) {
	if (exists $$global{aliases}{$alias}) {
	    carp "Alias $alias already exists in global, skipping";
	    delete $$self{aliases};
	    next;
	}
	$$global{aliases}{$alias} = $name;
	delete $$self{$alias};
    }
}

=head3 change_type(name, new_type)

Changes the type of a registration. Register_object will complain if
you try to re-register something as a new type, and just return the
original registration id. This function gets around that limitation.

=cut
sub change_type {
    my ($self, $name, $new_type) = @_;
    $$self{$name}{type} = $new_type;
}

=head1 AUTHOR

Copyright 2011 John Ralls, Fremont, California


    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
=cut

1;
