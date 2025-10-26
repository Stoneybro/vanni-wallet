"use client";

import { RiExternalLinkLine } from "react-icons/ri";
import { ChevronDownIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import CopyText from "./ui/copy";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { formatEth, formatTimestamp, truncateAddress } from "@/utils/format";
import {
  type AggregatedTransaction,
  type TransactionCategory,
} from "@/lib/blockscout/transactionAggregator";
import { BsArrowRepeat } from "react-icons/bs";
import { FaUsersGear } from "react-icons/fa6";
import { FaUsers } from "react-icons/fa6";
import { BsArrowUpRight } from "react-icons/bs";
import { BsArrowDownLeft } from "react-icons/bs";
import { MdOutlineNoteAdd } from "react-icons/md";
import { MdDeleteOutline } from "react-icons/md";
import { CiWallet } from "react-icons/ci";

interface TransactionItemProps {
  tx: AggregatedTransaction;
  walletAddress: `0x${string}`;
}

const getTxTypeLabel = (category: TransactionCategory): string => {
  switch (category) {
    case "deposit":
      return "Funds Received";
    case "execute_single":
      return "Single Payment";
    case "execute_batch":
      return "Batch Payment";
    case "intent_recurring_batch":
      return "Recurring Batch Payment";
    case "intent_recurring_single":
      return "Recurring Single Payment";
    case "intent_created":
      return "Recurring Payment Created";
    case "intent_cancelled":
      return "Recurring Payment Cancelled";
    case "wallet_deployed":
      return "Wallet Deployed";
    default:
      return "Transaction";
  }
};

const getTxTypeIcon = (category: TransactionCategory): React.ReactNode => {
  switch (category) {
    case "deposit":
      return <BsArrowDownLeft />;
    case "execute_single":
      return <BsArrowUpRight />;
    case "execute_batch":
      return <FaUsers />;
    case "intent_recurring_batch":
      return <FaUsersGear />;
    case "intent_recurring_single":
      return <BsArrowRepeat />;
    case "intent_created":
      return <MdOutlineNoteAdd />;
    case "intent_cancelled":
      return <MdDeleteOutline />;
    case "wallet_deployed":
      return <CiWallet />;
    default:
      return <RiExternalLinkLine />;
  }
};

export default function TransactionItem({ tx }: TransactionItemProps) {
  const valueEth = formatEth(tx.value);
  const gasEth = formatEth(tx.gasUsed ?? 0n);
  const label = getTxTypeLabel(tx.category);
  const icon = getTxTypeIcon(tx.category);

  // Format timestamp
  const formattedDate = formatTimestamp(tx.timestamp);
  const explorerUrl = `https://eth-sepolia.blockscout.com/tx/${tx.hash}`;

  const isCollapsible =
    tx.category === "execute_batch" || tx.category === "intent_recurring_batch";

  const renderDetails = () => {
    switch (tx.category) {
      case "intent_created":
      case "intent_cancelled":
        return (
          <div className='space-y-1'>
            {tx.intentId && (
              <div className='font-medium text-xs flex items-center gap-1'>
                Intent: <span>{truncateAddress(tx.intentId)}</span>{" "}
                <CopyText className='w-2!' text={tx.intentId} />
              </div>
            )}
            {tx.description && (
              <div className='text-xs text-muted-foreground'>
                {tx.description}
              </div>
            )}
          </div>
        );

      case "intent_recurring_single":
        return (
          <div className='space-y-1'>
            {tx.transactionCount !== undefined && (
              <div className='text-xs text-muted-foreground'>
                Payment #{tx.transactionCount + 1}
              </div>
            )}
            {tx.recipients && tx.recipients.length > 0 && (
              <div className='text-xs text-muted-foreground flex items-center gap-1'>
                To: <span>{truncateAddress(tx.recipients[0].address)}</span>{" "}
                <CopyText text={tx.recipients[0].address} />
              </div>
            )}
            {tx.value > 0n && (
              <div className='text-xs font-medium'>Value: {valueEth} ETH</div>
            )}
          </div>
        );

      case "intent_recurring_batch":
        return (
          <div>
            <div className='space-y-1'>
              {tx.transactionCount !== undefined && (
                <div className='text-xs text-muted-foreground'>
                  Payment #{tx.transactionCount + 1}
                </div>
              )}
              {tx.recipients && tx.recipients.length > 0 && (
                <div className='text-xs text-muted-foreground'>
                  To: {tx.recipients.length} recipient(s)
                </div>
              )}
              {tx.value > 0n && (
                <div className='text-xs font-medium'>Value: {valueEth} ETH</div>
              )}
            </div>
            <CollapsibleContent>
              <div className='space-y-1 rounded-md border px-2 py-1'>
                {tx.recipients?.map((recipient, index) => (
                  <div key={index} className='flex justify-between text-xs'>
                    <div className='flex items-center gap-1'>
                      To: <span>{truncateAddress(recipient.address)}</span>{" "}
                      <CopyText text={recipient.address} />
                    </div>
                    <span>Value: {formatEth(recipient.amount ?? 0n)} ETH</span>
                  </div>
                ))}
              </div>
            </CollapsibleContent>
          </div>
        );

      case "execute_batch":
        return (
          <div>
            <div className='space-y-1'>
              <div className='text-xs text-muted-foreground'>
                Recipients: {tx.recipients?.length}
              </div>
              <div className='text-xs text-muted-foreground'>
                Total value: {valueEth} ETH
              </div>
            </div>
            <CollapsibleContent>
              <div className='space-y-1 rounded-md border px-2 py-1'>
                {tx.recipients?.map((recipient, index) => (
                  <div key={index} className='flex justify-between text-xs'>
                    <div className='flex items-center gap-1'>
                      To: <span>{truncateAddress(recipient.address)}</span>{" "}
                      <CopyText text={recipient.address} />
                    </div>
                    <span>Value: {formatEth(recipient.amount || 0n)} ETH</span>
                  </div>
                ))}
              </div>
            </CollapsibleContent>
          </div>
        );

      case "execute_single":
        return (
          <div className='space-y-1'>
            <div className='text-xs text-muted-foreground flex items-center gap-1'>
              To: <span>{truncateAddress(tx.to)}</span>{" "}
              <CopyText text={tx.to} />
            </div>
            {tx.value > 0n && (
              <div className='text-xs text-muted-foreground'>
                value: {valueEth} ETH
              </div>
            )}
          </div>
        );

      case "deposit":
        return (
          <div className='text-xs text-muted-foreground flex items-center gap-1'>
            From: <span>{truncateAddress(tx.from)}</span>{" "}
            <CopyText text={tx.from} />
          </div>
        );

      case "wallet_deployed":
        return (
          <div className='text-xs text-muted-foreground'>
            {tx.description || "Smart wallet created"}
          </div>
        );

      default:
        if (tx.description) {
          return (
            <div className='text-xs text-muted-foreground'>
              {tx.description}
            </div>
          );
        }
        return null;
    }
  };

  const content = (
    <div
      className={`
        hover:bg-sidebar-accent hover:text-sidebar-accent-foreground
        flex flex-col gap-2.5 border-b p-4 text-sm leading-tight
        last:border-b-0 transition-colors `}
    >
      {/* Header Row */}
      <div className='flex justify-between items-start w-full gap-2'>
        <div className='flex items-center gap-2 flex-1 min-w-0'>
          <div className='flex flex-col min-w-0 flex-1'>
            <div className='flex items-center gap-1'>
              {icon}
              <span className={`font-semibold truncate`}>{label}</span>
            </div>
          </div>
        </div>
        {isCollapsible && (
          <CollapsibleTrigger asChild>
            <Button variant='ghost' size='icon-sm'>
              <ChevronDownIcon className='h-4 w-4' />
              <span className='sr-only'>Toggle</span>
            </Button>
          </CollapsibleTrigger>
        )}
      </div>

      {/* Details */}
      {renderDetails()}

      {/* Footer Row */}
      <div className='flex justify-between items-center w-full text-xs text-muted-foreground'>
        <div>{formattedDate}</div>
        <a
          href={explorerUrl}
          target='_blank'
          rel='noopener noreferrer'
          className='flex items-center gap-1 text-black underline'
        >
          <span>View</span>
          <RiExternalLinkLine />
        </a>
      </div>

      {tx.gasUsed !== undefined && tx.gasUsed > 0n && (
        <div className='text-xs opacity-50'>Gas: {gasEth} ETH</div>
      )}
    </div>
  );

  if (isCollapsible) {
    return <Collapsible>{content}</Collapsible>;
  }

  return content;
}
