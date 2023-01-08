<?php

declare(strict_types=1);

namespace danog\MadelineProto\Db;

use Amp\Iterator;
use Amp\Redis\Redis as RedisRedis;
use danog\MadelineProto\Db\Driver\Redis;
use danog\MadelineProto\Logger;
use danog\MadelineProto\Settings\Database\Redis as DatabaseRedis;
use Throwable;

/**
 * Redis database backend.
 */
class RedisArray extends DriverArray
{
    protected DatabaseRedis $dbSettings;
    private RedisRedis $db;

    // Legacy
    protected array $settings;

    /**
     * Initialize on startup.
     */
    public function initStartup()
    {
        return $this->initConnection($this->dbSettings);
    }
    protected function prepareTable(): void
    {
    }

    protected function renameTable(string $from, string $to): void
    {
        Logger::log("Moving data from {$from} to {$to}", Logger::WARNING);
        $from = "va:$from";
        $to = "va:$to";

        $request = $this->db->scan($from.'*');

        $lenK = \strlen($from);
        while ($request->advance()) {
            $oldKey = $request->getCurrent();
            $newKey = $to.\substr($oldKey, $lenK);
            $value = $this->db->get($oldKey);
            $this->db->set($newKey, $value);
            $this->db->delete($oldKey);
        }
    }

    /**
     * Initialize connection.
     */
    public function initConnection(DatabaseRedis $settings): void
    {
        if (!isset($this->db)) {
            $this->db = Redis::getConnection($settings);
        }
    }

    /**
     * Get redis key name.
     */
    private function rKey(string $key): string
    {
        return 'va:'.$this->table.':'.$key;
    }

    /**
     * Get iterator key.
     */
    private function itKey(): string
    {
        return 'va:'.$this->table.'*';
    }
    /**
     * Set value for an offset.
     *
     * @link https://php.net/manual/en/arrayiterator.offsetset.php
     * @param string $index <p>
     * The index to set for.
     * </p>
     * @throws Throwable
     */
    public function set(string|int $index, mixed $value): void
    {
        if ($this->hasCache($index) && $this->getCache($index) === $value) {
            return;
        }

        $this->setCache($index, $value);

        $this->db->set($this->rKey($index), \serialize($value));
        $this->setCache($index, $value);
    }

    public function offsetGet(mixed $offset): mixed
    {
        $offset = (string) $offset;
        if ($this->hasCache($offset)) {
            return $this->getCache($offset);
        }

        $value = $this->db->get($this->rKey($offset));

        if ($value !== null && $value = \unserialize($value)) {
            $this->setCache($offset, $value);
        }

        return $value;
    }

    public function unset(string|int $key): void
    {
        $this->unsetCache($key);

        $this->db->delete($this->rkey($key));
    }

    /**
     * Get array copy.
     *
     * @throws Throwable
     */
    public function getArrayCopy(): array
    {
        $iterator = $this->getIterator();
        $result = [];
        while ($iterator->advance()) {
            [$key, $value] = $iterator->getCurrent();
            $result[$key] = $value;
        }
        return $result;
    }

    public function getIterator(): Iterator
    {
        $request = $this->db->scan($this->itKey());

        $len = \strlen($this->rKey(''));
        while ($request->advance()) {
            $key = $request->getCurrent();
            $emit([\substr($key, $len), \unserialize($this->db->get($key))]);
        }
    }

    /**
     * Count elements.
     *
     * @link https://php.net/manual/en/arrayiterator.count.php
     * @return Promise<int> The number of elements or public properties in the associated
     * array or object, respectively.
     * @throws Throwable
     */
    public function count(): int
    {
        $request = $this->db->scan($this->itKey());
        $count = 0;

        while ($request->advance()) {
            $count++;
        }

        return $count;
    }

    /**
     * Clear all elements.
     */
    public function clear(): void
    {
        $this->clearCache();
        $request = $this->db->scan($this->itKey());

        $keys = [];
        $k = 0;
        while ($request->advance()) {
            $keys[$k++] = $request->getCurrent();
            if ($k === 10) {
                $this->db->delete(...$keys);
                $keys = [];
                $k = 0;
            }
        }
        if (!empty($keys)) {
            $this->db->delete(...$keys);
        }
    }
}
