<?php declare(strict_types=1);

namespace danog\MadelineProto\EventHandler\Message;

use danog\MadelineProto\MTProto;

/**
 * Represents an incoming private message.
 */
final class IncomingPrivateMessage extends PrivateMessage implements Incoming
{
    public readonly bool $out;

    /** @internal */
    public function __construct(
        MTProto $API,
        array $rawMessage
    ) {
        parent::__construct($API, $rawMessage);
        $this->out = false;
    }
}
